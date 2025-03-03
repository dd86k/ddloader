/// Minimum loader interface.
module ddloader;

version (Windows)
{
    import core.sys.windows.winbase; // LoadLibraryA, FreeLibrary, GetLastError
}
else version (Posix)
{
    // NOTE: Calling dlerror(3) clears the last error
    import core.sys.posix.dlfcn; // dlopen, dlclose, dlsym, dladdr, dlinfo, dlerror
}

import std.string;

struct DynamicLibraryError
{
    string library; // name
    string message;
}

struct DynamicLibrary
{
    void *handle;
    DynamicLibraryError[] errors;
}

class EmptySetLoaderException : Exception
{
    this()
    {
        super("List of libraries given is empty.");
    }
}
class InvalidSymbolLoaderException : Exception
{
    this()
    {
        super("Symbol name is null or empty.");
    }
}
class InvalidFunctionLoaderException : Exception
{
    this()
    {
        super("Function pointer cannot be null.");
    }
}
class BindFailedLoaderException : Exception
{
    this(string symbolname)
    {
        super(`Failed to bind "`~symbolname~`": `~librarySysError());
    }
}
class LoadFailedLoaderException : Exception
{
    this()
    {
        // It is not necessary to put all the errors in the message,
        // thanks to libraryErrors, it can be done on-demand.
        super(`Failed to load specified dynamic libraries.`);
    }
}

private
string librarySysError()
{
    version (Windows)
    {
        enum ERR_BUF_SZ = 256;
		__gshared char[ERR_BUF_SZ] buffer = void;
		size_t len = FormatMessageA(
			FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_MAX_WIDTH_MASK,
			null,
			GetLastError(),
			0,	// Default
			buffer.ptr,
			ERR_BUF_SZ, // uint
			null);
        
        // Prevent out of bounds exception caused by us
        if (len >= ERR_BUF_SZ) len = ERR_BUF_SZ;
		
        return len ? cast(string)(buffer[0..len].idup) : "Unknown error";
    }
    else version (Posix)
    {
        return fromStringz(dlerror()).idup;
    }
    else static assert(false, "Implement librarySysError()");
}

/// Load the first library in a set.
///
/// Given a list of library names, the loader will go in-order
/// and attempt to load at least one library.
///
/// On sucess, the first loaded library will be returned.
///
/// On failure, when no libraries could be loaded, an LoadFailedLoaderException
/// exception is thrown.
///
/// Params: libraries = Array of libraries to load.
/// Returns: Dynamic library instance.
DynamicLibrary libraryLoad(immutable(string)[] libraries...)
{
    if (libraries.length == 0)
        throw new EmptySetLoaderException();
    
    DynamicLibrary lib;
    
    foreach (name; libraries)
    {
        // If the string is null (by ptr) or empty (by length), toStringz passes
        // an empty string, so error out explicitly.
        //
        // This is more direct and clear than letting the system attempt to describe
        // the error, which is usually "Invalid handle", etc.
        if (name is null || name.length == 0)
            throw new InvalidSymbolLoaderException();
        
        // Using toStringz to safer in the case that a string in the array
        // was dynamically allocated, even if incredibly rare.
        version (Windows)
            lib.handle = LoadLibraryA(toStringz(name));
        else version (Posix)
            lib.handle = dlopen(toStringz(name), RTLD_LAZY);
        else
            static assert(false, "Implement libraryLoad");
        
        // Break as soon as a value is set.
        if (lib.handle)
            break;
        
        // Otherwise, add error that occured
        lib.errors ~= DynamicLibraryError(name, librarySysError());
    }
    
    // Couldn't load any of the specified libraries.
    if (lib.handle == null)
        throw new LoadFailedLoaderException();
    
    return lib;
}

/// Returns the list of errors for this library.
///
/// Only useful after using libraryLoad.
/// Params: lib = Dynamic library instance.
/// Returns: Error list, including library names and error message associated.
DynamicLibraryError[] libraryErrors(ref DynamicLibrary lib)
{
    return lib.errors;
}

/// Check if library is loaded.
/// Params: lib = Dynamic library instance.
/// Returns: True ifthe dynamic library handle is populated.
bool libraryIsLoaded(ref DynamicLibrary lib)
{
    return lib.handle != null;
}

/// Bind a symbol to a function.
///
/// Params:
///   lib = Dynamic library instance.
///   funcptr = Function pointer.
///   symbolname = Name of the symbol (currently only does exact matches).
void libraryBind(ref DynamicLibrary lib, void **funcptr, const(char) *symbolname)
{
    if (funcptr == null)
        throw new InvalidFunctionLoaderException();
    if (symbolname == null)
        throw new InvalidSymbolLoaderException();
    
    // The cast is account for a worst-case scenario where somehow,
    // the definition of these isn't returning void*.
    version (Windows)
        *funcptr = cast(void*)GetProcAddress(lib.handle, symbolname);
    else version (Posix)
        *funcptr = cast(void*)dlsym(lib.handle, symbolname);
    else
        static assert(false, "Implement libraryBind");
    
    // Couldn't bind the function.
    if (*funcptr == null)
        throw new BindFailedLoaderException(cast(string)fromStringz(symbolname));
}

/// Close dynamic library instance.
/// Params: lib = Dynamic library instance.
void libraryClose(ref DynamicLibrary lib)
{
    version (Windows)
        FreeLibrary(lib.handle);
    else version (Posix)
        dlclose(lib.handle);
    else
        static assert(false, "Implement libraryClose");
    
    // If closed, at least the loaded check won't fail.
    lib.handle = null;
}

version (Windows)
{
    unittest
    {
        assert(false, "todo");
    }
}
else version (Posix)
{
    import core.sys.posix.sys.utsname : utsname;
    
    extern (C) __gshared int function(utsname*) uname;
    
    unittest
    {
        DynamicLibrary lib = libraryLoad("libc.so.6");
        
        libraryBind(lib, cast(void**)&uname, "uname");
        
        utsname n;
        assert(uname(&n) == 0);
        assert(n.sysname[0]);
    }
}
