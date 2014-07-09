module LispVals where

import Data.Ratio (Ratio, numerator, denominator)
import Data.Complex (Complex((:+)))
import qualified Data.Vector as V (toList, Vector)
import Text.ParserCombinators.Parsec (ParseError)
import Control.Monad.Error (throwError, Error, noMsg, strMsg, catchError)

data LispVal = Atom String
        | List [LispVal]
        | Vector (V.Vector LispVal)
        | DottedList [LispVal] LispVal
        | Number Integer
        | String String
        | Bool Bool
        | Char Char
        | Float Float
        | Complex (Complex Float)
        | Ratio (Ratio Integer)

instance Show LispVal where show = showVal
showVal :: LispVal -> String
showVal (String contents) = "\"" ++ (unescapeString contents) ++ "\""
showVal (Atom name) = name
showVal (Number contents) = show contents
showVal (Bool True) = "#t"
showVal (Bool False) = "#f"
showVal (Char contents) = "#\\" ++ case contents of
                            '\n' -> "newline"
                            ' ' -> "space"
                            _ -> [contents]
showVal (List contents) = "(" ++ unwordsList contents ++ ")"
showVal (DottedList head tail) = "(" ++ unwordsList head ++ " . " ++ showVal tail ++ ")"
showVal (Vector contents) =
    "#(" ++ (unwordsList . V.toList) contents ++ ")"
showVal (Float contents) = show contents
showVal (Complex (r :+ i))
    | i > 0 = show r ++ "+" ++ show i ++ "i"
    | i < 0 = show r ++ show i ++ "i"
    | i == 0 = show r
showVal (Ratio contents) = show (numerator contents) ++ "/" ++ show (denominator contents)


data LispError = NumArgs Integer [LispVal]
               | TypeMismatch String LispVal
               | Parser ParseError
               | BadSpecialForm String LispVal
               | NotFunction String String
               | UnboundVar String String
               | Unspecified String
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
showError (Unspecified message) = "Unspecified operation: " ++ message

instance Show LispError where show = showError

instance Error LispError where
     noMsg = Default "An error has occurred"
     strMsg = Default

type ThrowsError = Either LispError

trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val

unwordsList :: [LispVal] -> String
unwordsList = unwords . map showVal

unescapeString :: String -> String
unescapeString [] = []
unescapeString (x:xs)
    | x == '\n' = "\\n" ++ unescapeString xs
    | x == '\t' = "\\t" ++ unescapeString xs
    | x == '\r' = "\\r" ++ unescapeString xs
    | x == '\"' = "\\\"" ++ unescapeString xs
    | x == '\\' = "\\\\" ++ unescapeString xs
    | otherwise = x : unescapeString xs
