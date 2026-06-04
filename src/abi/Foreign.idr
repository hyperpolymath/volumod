-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
||| Foreign Function Interface Declarations
|||
||| This module declares all C-compatible functions that will be
||| implemented in the Zig FFI layer.
|||
||| All functions are declared here with type signatures and safety proofs.
||| Implementations live in ffi/zig/

module {{PROJECT}}.ABI.Foreign

import {{PROJECT}}.ABI.Types
import {{PROJECT}}.ABI.Layout

%default total

--------------------------------------------------------------------------------
-- Library Lifecycle
--------------------------------------------------------------------------------

||| Initialize the library
||| Returns a handle to the library instance, or Nothing on failure
export
%foreign "C:{{project}}_init, lib{{project}}"
prim__init : PrimIO Bits64

||| Safe wrapper for library initialization
export
init : IO (Maybe Handle)
init = do
  ptr <- primIO prim__init
  pure (createHandle ptr)

||| Clean up library resources
export
%foreign "C:{{project}}_free, lib{{project}}"
prim__free : Bits64 -> PrimIO ()

||| Safe wrapper for cleanup
export
free : Handle -> IO ()
free h = primIO (prim__free (handlePtr h))

--------------------------------------------------------------------------------
-- Core Operations
--------------------------------------------------------------------------------

||| Example operation: process data
export
%foreign "C:{{project}}_process, lib{{project}}"
prim__process : Bits64 -> Bits32 -> PrimIO Bits32

||| Safe wrapper with error handling
export
process : Handle -> Bits32 -> IO (Either Result Bits32)
process h input = do
  result <- primIO (prim__process (handlePtr h) input)
  pure $ case result of
    0 => Left Error
    n => Right n

--------------------------------------------------------------------------------
-- String Operations
--------------------------------------------------------------------------------

||| Convert C string to Idris String
export
%foreign "support:idris2_getString, libidris2_support"
prim__getString : Bits64 -> String

||| Free C string
export
%foreign "C:{{project}}_free_string, lib{{project}}"
prim__freeString : Bits64 -> PrimIO ()

||| Get string result from library
export
%foreign "C:{{project}}_get_string, lib{{project}}"
prim__getResult : Bits64 -> PrimIO Bits64

||| Safe string getter
export
getString : Handle -> IO (Maybe String)
getString h = do
  ptr <- primIO (prim__getResult (handlePtr h))
  if ptr == 0
    then pure Nothing
    else do
      let str = prim__getString ptr
      primIO (prim__freeString ptr)
      pure (Just str)

--------------------------------------------------------------------------------
-- Array/Buffer Operations
--------------------------------------------------------------------------------

||| Process array data
export
%foreign "C:{{project}}_process_array, lib{{project}}"
prim__processArray : Bits64 -> Bits64 -> Bits32 -> PrimIO Bits32

||| Safe array processor
export
processArray : Handle -> (buffer : Bits64) -> (len : Bits32) -> IO (Either Result ())
processArray h buf len = do
  result <- primIO (prim__processArray (handlePtr h) buf len)
  pure $ case resultFromInt result of
    Just Ok => Right ()
    Just err => Left err
    Nothing => Left Error
  where
    resultFromInt : Bits32 -> Maybe Result
    resultFromInt 0 = Just Ok
    resultFromInt 1 = Just Error
    resultFromInt 2 = Just InvalidParam
    resultFromInt 3 = Just OutOfMemory
    resultFromInt 4 = Just NullPointer
    resultFromInt _ = Nothing

--------------------------------------------------------------------------------
-- Error Handling
--------------------------------------------------------------------------------

||| Get last error message
export
%foreign "C:{{project}}_last_error, lib{{project}}"
prim__lastError : PrimIO Bits64

||| Retrieve last error as string
export
lastError : IO (Maybe String)
lastError = do
  ptr <- primIO prim__lastError
  if ptr == 0
    then pure Nothing
    else pure (Just (prim__getString ptr))

||| Get error description for result code
export
errorDescription : Result -> String
errorDescription Ok = "Success"
errorDescription Error = "Generic error"
errorDescription InvalidParam = "Invalid parameter"
errorDescription OutOfMemory = "Out of memory"
errorDescription NullPointer = "Null pointer"

--------------------------------------------------------------------------------
-- Version Information
--------------------------------------------------------------------------------

||| Get library version
export
%foreign "C:{{project}}_version, lib{{project}}"
prim__version : PrimIO Bits64

||| Get version as string
export
version : IO String
version = do
  ptr <- primIO prim__version
  pure (prim__getString ptr)

||| Get library build info
export
%foreign "C:{{project}}_build_info, lib{{project}}"
prim__buildInfo : PrimIO Bits64

||| Get build information
export
buildInfo : IO String
buildInfo = do
  ptr <- primIO prim__buildInfo
  pure (prim__getString ptr)

--------------------------------------------------------------------------------
-- Callback Support
--------------------------------------------------------------------------------

||| Callback function type (C ABI shape).
|||
||| **Implementation note for cartridge instantiation.**
|||
||| Idris2 closures are not C-callable: their calling convention is the
||| runtime's, not the platform C ABI. Passing one as a function pointer
||| via `believe_me` produces undefined behaviour on any non-trivial
||| closure, even though it type-checks. The previous template body
||| did exactly that and shipped the unsafe idiom to every downstream
||| cartridge; it has been removed.
|||
||| The correct pattern is a callback **registry**:
|||
|||   1. Idris2 stores the closure in an IORef'd map keyed by an `Int` id.
|||   2. The C side accepts the `id`, not a function pointer:
|||      `{{project}}_register_callback_by_id(handle, id) -> Result`
|||   3. A single C-callable dispatcher is exported from Idris2 via
|||      `%foreign export "C:{{project}}_dispatch_callback"`; the C side
|||      invokes it with `(id, arg1, arg2)` and the dispatcher looks
|||      up the closure by id and runs it.
|||
||| Each cartridge implements the registry against its own state:
||| storing callbacks needs cartridge-specific concurrency choices
||| (single-threaded IORef vs. atomic / MVar, lifetime model, removal
||| semantics) that should be made deliberately, not inherited from a
||| scaffold. The Zig side in `ffi/zig/src/main.zig` must be updated
||| in lockstep to take `(handle, id)` instead of `(handle, fn_ptr)`.
public export
Callback : Type
Callback = Bits64 -> Bits32 -> Bits32

-- registerCallback is intentionally not provided in this template;
-- a cartridge that needs C-side callbacks instantiates a registry
-- per the doc-block above.

--------------------------------------------------------------------------------
-- Utility Functions
--------------------------------------------------------------------------------

||| Check if library is initialized
export
%foreign "C:{{project}}_is_initialized, lib{{project}}"
prim__isInitialized : Bits64 -> PrimIO Bits32

||| Check initialization status
export
isInitialized : Handle -> IO Bool
isInitialized h = do
  result <- primIO (prim__isInitialized (handlePtr h))
  pure (result /= 0)
