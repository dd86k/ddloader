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
    string library;
    string message;
}

struct DynamicLibrary
{
    void *handle;
    DynamicLibraryError[] errors;
}

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
			ERR_BUF_SZ,
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

DynamicLibrary libraryLoad(immutable(string)[] libraries...)
{
    if (libraries.length == 0)
        throw new Exception("No libraries given");
    
    DynamicLibrary lib;
    
    foreach (name; libraries)
    {
        version (Windows)
            lib.handle = LoadLibraryA(toStringz(name));
        else version (Posix)
            lib.handle = dlopen(toStringz(name), RTLD_LAZY);
        else
            static assert(false, "Implement libraryLoad(immutable(string)[]...)");
        
        // Break as soon as a value is set.
        if (lib.handle)
            break;
        
        // Otherwise, add error that occured
        DynamicLibraryError err;
        err.library = name;
        err.message = librarySysError();
        lib.errors ~= err;
    }
    
    // Otherwise, null on error.
    // Error message will be set according to last library.
    if (lib.handle == null)
    {
        string post;
        foreach (i, err; lib.errors)
        {
            if (i) post ~= `, `;
            post ~= err.library ~ `: "` ~ err.message ~ `"`;
        }
        throw new Exception(`Failed to load dynamic libraries: `~post);
    }
    
    return lib;
}

void libraryBind(ref DynamicLibrary lib, void **funcptr, const(char) *symbolname)
{
    if (funcptr == null)
        throw new Exception("Function pointer cannot be null");
    if (funcptr == null)
        throw new Exception("Symbol string cannot be null");
    
    version (Windows)
        *funcptr = GetProcAddress(lib.handle, symbolname);
    else version (Posix)
        *funcptr = dlsym(lib.handle, symbolname);
    else
        static assert(false, "Implement libraryBind(ref DynamicLibrary, void**, string)");
    
    if (*funcptr == null)
        throw new Exception(
            `Failed to bind "`~cast(string)fromStringz(symbolname)~`": `~librarySysError());
}

void libraryClose(ref DynamicLibrary lib)
{
    version (Windows)
        FreeLibrary(lib.handle);
    else version (Posix)
        dlclose(lib.handle);
    else
        static assert(false, "Implement libraryClose(ref DynamicLibrary)");
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
    }
}
