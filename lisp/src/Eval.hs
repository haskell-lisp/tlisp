{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE Rank2Types #-}

module Eval where
import Parse

import Text.ParserCombinators.Parsec (ParseError)
import Control.Monad (liftM, foldM)
import Control.Monad.Error (throwError, Error, noMsg, strMsg, catchError)
import Data.Ratio (Ratio, (%))
import Data.Complex (Complex((:+)))

eval :: LispVal -> ThrowsError LispVal
eval val@(String _) = return val
eval val@(Number _) = return val
eval val@(Bool _) = return val
eval val@(Complex _) = return val
eval val@(Ratio _) = return val
eval val@(Float _) = return val
eval val@(Char _) = return val
eval (List [Atom "quote", val]) = return val
eval (List [Atom "if", pred, conseq, alt]) =
    do result <- eval pred
       case result of
         Bool False -> eval alt
         otherwise -> eval conseq
eval (List (Atom func : args)) = mapM eval args >>= apply func
eval (List (val:[])) = eval val
eval badForm = throwError $ BadSpecialForm "Unrecognized special form" badForm

apply :: String -> [LispVal] -> ThrowsError LispVal
apply func args = maybe (throwError $ NotFunction "Unrecognized primitive function args" func)
                        ($ args)
                        (lookup func primitives)

primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", anyNumListOp (+)),
              ("-", anyNumListOp (-)),
              ("*", anyNumListOp (*)),
              ("/", anyNumListDiv),
              ("mod", onlyNumListOp mod),
              ("quotient", onlyNumListOp quot),
              ("remainder", onlyNumListOp rem),
              ("=", anyEqBoolListOp (==)), --FIXME these don't with more than 2 args yet
              ("<", anyOrdBoolListOp (<)),
              (">", anyOrdBoolListOp (>)),
              ("/=", anyEqBoolListOp (/=)),
              (">=", anyOrdBoolListOp (>=)),
              ("<=", anyOrdBoolListOp (<=)),
              ("&&", boolBoolBinop (&&)),
              ("||", boolBoolBinop (||)),
              ("string=?", strBoolBinop (==)),
              ("string<=?", strBoolBinop (<=)),
              ("string>=?", strBoolBinop (>=)),
              ("string<?", strBoolBinop (<)),
              ("string>?", strBoolBinop (>)),
              ("car", car),
              ("cdr", cdr),
              ("cons", cons),
              ("eq?", eqv),
              ("eqv?", eqv),
              ("equal?", equal),
              ("string?", isLispValTest (isLispValString)),
              ("boolean?", isLispValTest (isLispValBool)),
              ("number?", isLispValTest (isLispValNum)),
              ("complex?", isLispValTest (isLispValComplex)),
              ("real?", isLispValTest (isLispValReal)),
              ("rational?", isLispValTest (isLispValRational)),
              ("integer?", isLispValTest (isLispValInteger)),
              ("vector?", isLispValTest (isLispValVector)),
              ("char?", isLispValTest (isLispValChar)),
              ("port?", undefined),
              ("procedure?", undefined),
              ("pair?", isLispValTest (isLispValDottedList)),
              ("symbol?", isLispValTest (isLispValAtom)),
              ("list?", isLispValTest (isLispValList)),
              ("symbol->string", symbolToString),
              ("string->symbol", stringToSymbol)]

stringToSymbol :: [LispVal] -> ThrowsError LispVal
stringToSymbol ((String s):[]) = return $ Atom s
stringToSymbol (e:[]) = throwError $ TypeMismatch "string" e
stringToSymbol e = throwError $ NumArgs 1 e

symbolToString :: [LispVal] -> ThrowsError LispVal
symbolToString ((Atom s):[]) = return $ String s
symbolToString (e:[]) = throwError $ TypeMismatch "symbol" e
symbolToString e = throwError $ NumArgs 1 e

isLispValDottedList :: LispVal -> Bool
isLispValDottedList (DottedList _ _) = True
isLispValDottedList _ = False

isLispValList :: LispVal -> Bool
isLispValList (List _) = True
isLispValList _ = False

isLispValAtom :: LispVal -> Bool
isLispValAtom (Atom _) = True
isLispValAtom _ = False

isLispValVector :: LispVal -> Bool
isLispValVector (Vector _) = True
isLispValVector _ = False

isLispValChar :: LispVal -> Bool
isLispValChar (Char _) = True
isLispValChar _ = False

isLispValInteger :: LispVal -> Bool
isLispValInteger (Number _) = True
isLispValInteger _ = False

isLispValRational :: LispVal -> Bool
isLispValRational (Number _) = True
isLispValRational (Ratio _) = True
isLispValRational _ = False

isLispValReal :: LispVal -> Bool
isLispValReal (Number _) = True
isLispValReal (Float _) = True
isLispValReal (Ratio _) = True
isLispValReal _ = False

isLispValComplex :: LispVal -> Bool
isLispValComplex (Number _) = True
isLispValComplex (Float _) = True
isLispValComplex (Ratio _) = True
isLispValComplex (Complex _) = True
isLispValComplex _ = False

isLispValNum :: LispVal -> Bool
isLispValNum (Number _) = True
isLispValNum (Float _) = True
isLispValNum (Ratio _) = True
isLispValNum (Complex _) = True
isLispValNum _ = False

isLispValBool :: LispVal -> Bool
isLispValBool (Bool _) = True
isLispValBool _ = False

isLispValString :: LispVal -> Bool
isLispValString (String _) = True
isLispValString _ = False

isLispValTest :: (LispVal -> Bool) -> [LispVal] -> ThrowsError LispVal
isLispValTest f (l:[]) = return $ Bool $ f l
isLispValTest _ e = throwError $ NumArgs 1 e

onlyNumListOp :: (forall a. Integral a => a -> a -> a) -> [LispVal] -> ThrowsError LispVal
onlyNumListOp f (l:ls@(_:_)) = foldM (onlyNumBinOp f) l ls
onlyNumListOp _ badArgList = throwError $ NumArgs 2 badArgList

onlyNumBinOp :: (forall a. Integral a => a -> a -> a) -> LispVal -> LispVal -> ThrowsError LispVal
onlyNumBinOp f (Number a) (Number b) = return $ Number (f a b)
onlyNumBinOp _ (Number _) e = throwError $ TypeMismatch "integral" e
onlyNumBinOp _ e _ = throwError $ TypeMismatch "integral" e

anyNumListDiv :: [LispVal] -> ThrowsError LispVal
anyNumListDiv (l:ls@(_:_)) = foldM (anyNumBinDiv) l ls
anyNumListDiv badArgList = throwError $ NumArgs 2 badArgList

anyNumBinDiv :: LispVal -> LispVal -> ThrowsError LispVal
anyNumBinDiv (Number a) (Number b) = return $ Number (div a b)
anyNumBinDiv (Number a) (Float b) = return $ Float ((fromIntegral a) / b)
anyNumBinDiv (Number a) (Complex b) = return $ Complex ((fromIntegral a :+ 0) / b)
anyNumBinDiv (Number a) (Ratio b) = return $ Ratio ((a % 1) / b)
anyNumBinDiv (Float a) (Number b) = return $ Float (a / (fromIntegral b))
anyNumBinDiv (Float a) (Float b) = return $ Float (a / b)
anyNumBinDiv (Float a) (Complex b) = return $ Complex ((a :+ 0) / b)
anyNumBinDiv (Float a) (Ratio b) = return $ Float (a / (fromRational b))
anyNumBinDiv (Complex a) (Number b) = return $ Complex (a / (fromIntegral b :+ 0))
anyNumBinDiv (Complex a) (Float b) = return $ Complex (a / (b :+ 0))
anyNumBinDiv (Complex a) (Complex b) = return $ Complex (a / b)
anyNumBinDiv (Complex a) (Ratio b) = return $ Complex (a / (fromRational b :+ 0))
anyNumBinDiv (Ratio a) (Number b) = return $ Ratio (a / (b % 1))
anyNumBinDiv (Ratio a) (Float b) = return $ Float (fromRational a / b)
anyNumBinDiv (Ratio a) (Complex b) = return $ Complex (fromRational a / b)
anyNumBinDiv (Ratio a) (Ratio b) = return $ Ratio (a / b)
anyNumBinDiv e _ = throwError $ TypeMismatch "number" e

anyNumListOp :: (forall a. Num a => a -> a -> a) -> [LispVal] -> ThrowsError LispVal
anyNumListOp f (l:ls@(_:_)) = foldM (anyNumBinOp f) l ls
anyNumListOp _ badArgList = throwError $ NumArgs 2 badArgList

anyNumBinOp :: (forall a. Num a => a -> a -> a) -> LispVal -> LispVal -> ThrowsError LispVal
anyNumBinOp f (Number a) (Number b) = return $ Number (f a b)
anyNumBinOp f (Number a) (Float b) = return $ Float (f (fromIntegral a) b)
anyNumBinOp f (Number a) (Complex b) = return $ Complex (f (fromIntegral a :+ 0) b)
anyNumBinOp f (Number a) (Ratio b) = return $ Ratio (f (a % 1) b)
anyNumBinOp f (Float a) (Number b) = return $ Float (f a (fromIntegral b))
anyNumBinOp f (Float a) (Float b) = return $ Float (f a b)
anyNumBinOp f (Float a) (Complex b) = return $ Complex (f (a :+ 0) b)
anyNumBinOp f (Float a) (Ratio b) = return $ Float (f a (fromRational b))
anyNumBinOp f (Complex a) (Number b) = return $ Complex (f a (fromIntegral b :+ 0))
anyNumBinOp f (Complex a) (Float b) = return $ Complex (f a (b :+ 0))
anyNumBinOp f (Complex a) (Complex b) = return $ Complex (f a b)
anyNumBinOp f (Complex a) (Ratio b) = return $ Complex (f a (fromRational b :+ 0))
anyNumBinOp f (Ratio a) (Number b) = return $ Ratio (f a (b % 1))
anyNumBinOp f (Ratio a) (Float b) = return $ Float (f (fromRational a) b)
anyNumBinOp f (Ratio a) (Complex b) = return $ Complex (f (fromRational a) b)
anyNumBinOp f (Ratio a) (Ratio b) = return $ Ratio (f a b)
anyNumBinOp _ e _ = throwError $ TypeMismatch "number" e

anyEqBoolListOp :: (forall a. Eq a => a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
anyEqBoolListOp f (l:ls:[]) = anyEqBoolBinOp (f) l ls
anyEqBoolListOp _ badArgList = throwError $ NumArgs 2 badArgList

anyEqBoolBinOp :: (forall a. Eq a => a -> a -> Bool) -> LispVal -> LispVal -> ThrowsError LispVal
anyEqBoolBinOp f (Number a) (Number b) = return $ Bool (f a b)
anyEqBoolBinOp f (Number a) (Float b) = return $ Bool (f (fromIntegral a) b)
anyEqBoolBinOp f (Number a) (Complex b) = return $ Bool (f (fromIntegral a :+ 0) b)
anyEqBoolBinOp f (Number a) (Ratio b) = return $ Bool (f (a % 1) b)
anyEqBoolBinOp f (Float a) (Number b) = return $ Bool (f a (fromIntegral b))
anyEqBoolBinOp f (Float a) (Float b) = return $ Bool (f a b)
anyEqBoolBinOp f (Float a) (Complex b) = return $ Bool (f (a :+ 0) b)
anyEqBoolBinOp f (Float a) (Ratio b) = return $ Bool (f a (fromRational b))
anyEqBoolBinOp f (Complex a) (Number b) = return $ Bool (f a (fromIntegral b :+ 0))
anyEqBoolBinOp f (Complex a) (Float b) = return $ Bool (f a (b :+ 0))
anyEqBoolBinOp f (Complex a) (Complex b) = return $ Bool (f a b)
anyEqBoolBinOp f (Complex a) (Ratio b) = return $ Bool (f a (fromRational b :+ 0))
anyEqBoolBinOp f (Ratio a) (Number b) = return $ Bool (f a (b % 1))
anyEqBoolBinOp f (Ratio a) (Float b) = return $ Bool (f (fromRational a) b)
anyEqBoolBinOp f (Ratio a) (Complex b) = return $ Bool (f (fromRational a) b)
anyEqBoolBinOp f (Ratio a) (Ratio b) = return $ Bool (f a b)
anyEqBoolBinOp _ e _ = throwError $ TypeMismatch "number" e

anyOrdBoolListOp :: (forall a. Ord a => a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
anyOrdBoolListOp f (l:ls:[]) = anyOrdBoolBinOp (f) l ls
anyOrdBoolListOp _ badArgList = throwError $ NumArgs 2 badArgList

anyOrdBoolBinOp :: (forall a. Ord a => a -> a -> Bool) -> LispVal -> LispVal -> ThrowsError LispVal
anyOrdBoolBinOp f (Number a) (Number b) = return $ Bool (f a b)
anyOrdBoolBinOp f (Number a) (Float b) = return $ Bool (f (fromIntegral a) b)
anyOrdBoolBinOp f (Number a) e@(Complex _) = throwError $ TypeMismatch "ordered" e
anyOrdBoolBinOp f (Number a) (Ratio b) = return $ Bool (f (a % 1) b)
anyOrdBoolBinOp f (Float a) (Number b) = return $ Bool (f a (fromIntegral b))
anyOrdBoolBinOp f (Float a) (Float b) = return $ Bool (f a b)
anyOrdBoolBinOp f (Float a) e@(Complex _) = throwError $ TypeMismatch "ordered" e
anyOrdBoolBinOp f (Float a) (Ratio b) = return $ Bool (f a (fromRational b))
anyOrdBoolBinOp f e@(Complex _) _ = throwError $ TypeMismatch "ordered" e
anyOrdBoolBinOp f (Ratio a) (Number b) = return $ Bool (f a (b % 1))
anyOrdBoolBinOp f (Ratio a) (Float b) = return $ Bool (f (fromRational a) b)
anyOrdBoolBinOp f (Ratio a) e@(Complex _) = throwError $ TypeMismatch "ordered" e
anyOrdBoolBinOp f (Ratio a) (Ratio b) = return $ Bool (f a b)
anyOrdBoolBinOp _ e _ = throwError $ TypeMismatch "number" e

boolBinop :: (LispVal -> ThrowsError a) -> (a -> a -> Bool) -> [LispVal] -> ThrowsError LispVal
boolBinop unpacker op args = if length args /= 2
                             then throwError $ NumArgs 2 args
                             else do left <- unpacker $ args !! 0
                                     right <- unpacker $ args !! 1
                                     return $ Bool $ left `op` right

strBoolBinop = boolBinop unpackStr
boolBoolBinop = boolBinop unpackBool

unpackNum :: LispVal -> ThrowsError Integer
unpackNum (Number n) = return n
unpackNum (List [n]) = unpackNum n
unpackNum notNum = throwError $ TypeMismatch "number" notNum

unpackComplex :: LispVal -> ThrowsError (Complex Float)
unpackComplex (Complex n) = return n
unpackComplex (Number n) = return ((fromIntegral n) :+ 0)
unpackComplex (Float n) = return (n :+ 0)
unpackComplex (Ratio n) = return ((fromRational n) :+ 0)
unpackComplex (List [n]) = unpackComplex n
unpackComplex notNum = throwError $ TypeMismatch "number" notNum

unpackRatio :: LispVal -> ThrowsError (Ratio Integer)
unpackRatio (Ratio n) = return n
unpackRatio (Number n) = return (n % 1)
unpackRatio (List [n]) = unpackRatio n
unpackRatio notNum = throwError $ TypeMismatch "number" notNum

unpackFloat :: LispVal -> ThrowsError Float
unpackFloat (Float n) = return n
unpackFloat (Ratio n) = return (fromRational n)
unpackFloat (Number n) = return (fromIntegral n)
unpackFloat (List [n]) = unpackFloat n
unpackFloat notNum = throwError $ TypeMismatch "number" notNum

unpackStr :: LispVal -> ThrowsError String
unpackStr (String s) = return s
unpackStr (Number s) = return $ show s
unpackStr (Complex s) = return $ show s
unpackStr (Float s) = return $ show s
unpackStr (Ratio s) = return $ show s
unpackStr (Bool s) = return $ show s
unpackStr notString = throwError $ TypeMismatch "string" notString

unpackBool :: LispVal -> ThrowsError Bool
unpackBool (Bool b) = return b
unpackBool notBool = throwError $ TypeMismatch "boolean" notBool

car :: [LispVal] -> ThrowsError LispVal
car [List (x : xs)] = return x
car [DottedList (x : xs) _] = return x
car [badArg] = throwError $ TypeMismatch "pair" badArg
car badArgList = throwError $ NumArgs 1 badArgList

cdr :: [LispVal] -> ThrowsError LispVal
cdr [List (x : xs)] = return $ List xs
cdr [DottedList (_ : xs) x] = return $ DottedList xs x
cdr [DottedList _ x] = return x
cdr [badArg] = throwError $ TypeMismatch "pair" badArg
cdr badArgList = throwError $ NumArgs 1 badArgList

cons :: [LispVal] -> ThrowsError LispVal
cons [x1, List []] = return $ List [x1]
cons [x, List xs] = return $ List $ [x] ++ xs
cons [x, DottedList xs xlast] = return $ DottedList ([x] ++ xs) xlast
cons [x1, x2] = return $ DottedList [x1] x2
cons badArgList = throwError $ NumArgs 2 badArgList

eqv :: [LispVal] -> ThrowsError LispVal
eqv [(Bool arg1), (Bool arg2)] = return $ Bool $ arg1 == arg2
eqv [(Number arg1), (Number arg2)] = return $ Bool $ arg1 == arg2
eqv [(Ratio arg1), (Ratio arg2)] = return $ Bool $ arg1 == arg2
eqv [(Float arg1), (Float arg2)] = return $ Bool $ arg1 == arg2
eqv [(Complex arg1), (Complex arg2)] = return $ Bool $ arg1 == arg2
eqv [(String arg1), (String arg2)] = return $ Bool $ arg1 == arg2
eqv [(Atom arg1), (Atom arg2)] = return $ Bool $ arg1 == arg2
eqv [(DottedList xs x), (DottedList ys y)] = eqv [List $ xs ++ [x], List $ ys ++ [y]]
eqv [(List arg1), (List arg2)] = return $ Bool $ (length arg1 == length arg2) &&
                                                    (and $ map eqvPair $ zip arg1 arg2)
    where eqvPair (x1, x2) = case eqv [x1, x2] of
                               Left err -> False
                               Right (Bool val) -> val
eqv [_, _] = return $ Bool False
eqv badArgList = throwError $ NumArgs 2 badArgList

data EqUnpacker = forall a. Eq a => AnyEqUnpacker (LispVal -> ThrowsError a)

unpackEquals :: LispVal -> LispVal -> EqUnpacker -> ThrowsError Bool
unpackEquals arg1 arg2 (AnyEqUnpacker unpacker) =
             do unpacked1 <- unpacker arg1
                unpacked2 <- unpacker arg2
                return $ unpacked1 == unpacked2
        `catchError` (const $ return False)

equal :: [LispVal] -> ThrowsError LispVal
equal [(List arg1), (List arg2)] = return $ Bool $ (length arg1 == length arg2) &&
                                                    (and $ map eqvPair $ zip arg1 arg2)
    where eqvPair (x1, x2) = case equal [x1, x2] of
                               Left err -> False
                               Right (Bool val) -> val
equal [arg1, arg2] = do
    primitiveEquals <- liftM or $ mapM (unpackEquals arg1 arg2)
                      [AnyEqUnpacker unpackNum, AnyEqUnpacker unpackRatio, AnyEqUnpacker unpackFloat,
                        AnyEqUnpacker unpackComplex, AnyEqUnpacker unpackStr, AnyEqUnpacker unpackBool]
    eqvEquals <- eqv [arg1, arg2]
    return $ Bool $ (primitiveEquals || let (Bool x) = eqvEquals in x)
equal badArgList = throwError $ NumArgs 2 badArgList


data LispError = NumArgs Integer [LispVal]
               | TypeMismatch String LispVal
               | Parser ParseError
               | BadSpecialForm String LispVal
               | NotFunction String String
               | UnboundVar String String
               | Default String

showError :: LispError -> String
showError (UnboundVar message varname) = message ++ ": " ++ varname
showError (BadSpecialForm message form) = message ++ ": " ++ show form
showError (NotFunction message func) = message ++ ": " ++ show func
showError (NumArgs expected found) = "Expected " ++ show expected
                                  ++ " args; found values " ++ unwordsList found
showError (TypeMismatch expected found) = "Invalid type: expected " ++ expected
                                       ++ ", found " ++ show found
showError (Parser parseErr) = "Parse error at " ++ show parseErr

instance Show LispError where show = showError

instance Error LispError where
     noMsg = Default "An error has occurred"
     strMsg = Default

type ThrowsError = Either LispError

trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val
