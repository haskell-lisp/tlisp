{-# LANGUAGE CPP #-}
module Main where
import Parse
import Eval

import System.IO (hFlush, stdout)
import System.Environment (getArgs)
import Text.ParserCombinators.Parsec (parse)
import Control.Monad (liftM, when)
import Control.Monad.Error (throwError)
#ifdef LIBEDITLINE
import System.Console.Editline.Readline (readline, addHistory, setInhibitCompletion)
#else
import System.Console.Readline (readline, addHistory, setInhibitCompletion)
#endif
import Data.Char (isSpace)

main :: IO ()
main = do args <- getArgs
          case length args of
              0 -> runRepl
              1 -> evalAndPrint $ args !! 0
              otherwise -> putStrLn "Program takes only 0 or 1 argument"

readExpr :: String -> ThrowsError LispVal
readExpr input = case parse parseExpr "lisp" input of
    Left err -> throwError $ Parser err
    Right val -> return val

evalString :: String -> IO String
evalString expr = return $ extractValue $ trapError (liftM show $ readExpr expr >>= eval)

evalAndPrint :: String -> IO ()
evalAndPrint expr =  evalString expr >>= putStrLn

runRepl :: IO ()
runRepl = do
    setInhibitCompletion True
    replLoop

replLoop :: IO ()
replLoop = do
    maybeLine <- readline "tlisp>>> "
    case maybeLine of
        Nothing -> return ()
        Just ":quit" -> return ()
        Just ":q" -> return ()
        Just line -> do
            let trimmedLine = dropWhile (isSpace) line
            when (not $ null trimmedLine) $ addHistory trimmedLine
            evalAndPrint trimmedLine
            replLoop
