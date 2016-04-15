module vulkan.registry;

import std.stdio, std.algorithm, std.range, std.meta, std.format;
import std.typecons, std.variant, std.traits, std.string, std.range;

import arsd.dom;

private void print(Args...)()
{
    pragma (msg, [Args].join.array);

    foreach (arg; Args)
        write(arg, " ");

    writeln();
}

private To convPrimitive(To)(string from)
{
    import std.conv : to, parse, ConvException;
    import std.traits : isUnsigned, EnumMembers;

    static if (isUnsigned!To)
    {
        try
            return from.to!To;
        catch (ConvException _)
        { }
        return from.parse!To(16);
    }
    else static if (is(To == enum) && is(To : string))
    {
        switch (from)
        {
            foreach (member; EnumMembers!To)
                case member:
                    return member;
            default:
                assert (0, "Unknown enum member: " ~ from ~ 
                        " allowed are " ~ [EnumMembers!To].to!string);
        }
    }
    else static if (is(To == VariantN!(VS, AllowedTypes), size_t VS, AllowedTypes...))
    {
        foreach (PossibleType; AllowedTypes)
            try
                return To(from.parse!PossibleType);
            catch (ConvException _)
            { }

        assert (0, "Error parsing: " ~ from);
    }
    else
        return from.to!To;
}

T deserialize(T, uint depth = 0, bool allowFailure = false)(arsd.dom.Element currentNode)
    //if (is(T == struct))
{
    enum isPrimitive(T) = is(T == string) || is(T == enum) || isScalarType!T;
    enum isStruct(T) = is(T == struct);
    enum isVariant(T) = is(T == VariantN!(VS, TL), size_t VS, TL...);
    template isPrimitiveOrVariantPrimitive(T)
    {
        static if (isPrimitiveBase!T)
            enum isPrimitive = true;
        else static if (is(T == VariantN!(VS, TL), size_t VS, TL...))
            enum isPrimitive = allSatisfy!(isPrimitiveBase, TL);
        else
            enum isPrimitive = false;
    }    

    enum indent1 = ' '.repeat(depth * 4).array;
    enum indent2 = ' '.repeat((depth + 1) * 4).array;
    string txt = currentNode.toString;
    string nodeTag = currentNode.tagName;
    print!(indent1 ~ T.stringof);

    // Deserialize primitive from XML element body
    static if (isPrimitive!T)
    {
        print!(indent2 ~ "Primitive: '" ~ " " ~ "' of type: ", T.stringof);
        return currentNode.outerText.convPrimitive!T;
    }
    else static if (is(T == VariantN!(_, TL), size_t _, TL...))
    {
        print!(indent2 ~ "Variant: '" ~ " " ~ "' of type: ", T.stringof);
        static if (allSatisfy!(isStruct, TL))
        {
            switch (currentNode.tagName)
            {
                foreach (AT; TL) case AT.stringof.toLower():
                {
                    auto type3 = AT.stringof.toLower();
                    auto type4 = currentNode.tagName;
                    return T(currentNode.deserialize!(AT, depth + 2));
                }
                default:
                {
                    writefln("Unknown tag: %s, expected: %s", currentNode.tagName, TL.stringof);
                    assert (0);
                }
            }
        }
        else static if (is(T == VariantN!(__, Var[], string), size_t __, Var))
        {
            //try
            //{
                return T(currentNode.innerText.convPrimitive!string);
            //}            
            //catch (DecodeException _)
            //{
            //    Var[] result;
            //
            //    string type5 = T.stringof;
            //
            //    foreach (elem; currentNode.childNodes)
            //    {
            //        string elemTag = elem.tagName;
            //        string varType = Var.stringof;
            //        auto tmpvar = elem.deserialize!(Var, depth + 2);
            //        result ~= tmpvar;
            //    }
            //
            //    return T(result);
            //}
        }
        else
            static assert (0, "Unhandled type: " ~ T.stringof ~ "!");
    }
    else static if (isStruct!T)
    {
        T result;

        foreach (idx, _; result.tupleof)
        {
            enum Name = T.tupleof[idx].stringof;
            static if (is(typeof(T.tupleof[idx]) == MyNullable!X, X))
            {
                alias Type = X;
                enum optional = true;
            }
            else 
            {
                alias Type = typeof(T.tupleof[idx]);
                enum optional = false;
            }
            enum optionalTxt = optional ? "Opt " : "Req ";

            string type = Type.stringof;
            string name = Name;

            print!(indent2 ~ "Struct Member: '" ~ Name ~
                   "' of type: ", optionalTxt ~ Type.stringof);

            // Skip struct member starting with underscore
            static if (Name[0] == '_')
            {
            }
            // Deserialize struct member from XML element body
            else static if (Name == "contents") 
            {
                static if (isPrimitive!Type)
                {
                    result.tupleof[idx] = currentNode.outerText.convPrimitive!Type;
                }
                else static if (isVariant!Type)
                {
                    result.tupleof[idx] = currentNode.deserialize!(Type, depth + 2);
                }
                else static if (is(Type == E[], E))
                {
                    foreach (elem; currentNode.childNodes)
                        if (elem.tagName != "#text")
                            result.tupleof[idx] ~= elem.deserialize!(E, depth + 2);
                }
                else
                    static assert (is(Type == E[], E));
                
            }
            // Deserialize struct member from XML tag attribute
            else
            {
                if (Name !in currentNode.attributes)
                {
                    static if (optional)
                        continue;
                    else
                        assert(0, format("%s %s", currentNode.tagName, currentNode.attributes));
                }
                auto contents = currentNode.attributes[Name];

                static if (isPrimitive!Type)
                    result.tupleof[idx] = contents.convPrimitive!Type;

                else static if (is(Type == E[], E) && isPrimitive!E)
                    result.tupleof[idx] = contents.split(',')
                        .map!(s => s.strip.convPrimitive!E).array;
                else
                    static assert (0, "Unhandled type: " ~ Type.stringof ~ "!");
            }
        }

        return result;
    }
    else
        static assert (0, "Unhandled type: " ~ T.stringof ~ "!");    

    //assert (0);
}

alias Required(T) = T;
alias Optional(T) = MyNullable!T;
enum ValidIf(alias condition) = true;

struct MyNullable(T)
{
    Nullable!T val;

    this(T data) { val = data; }

    void opAssign(T data) { val = data; }

    bool isNull() { return val.isNull(); }

    alias val this;

    string toString()
    {
        import std.conv : to;
        return val.isNull? "Nullable.null" : val.get.to!string;
    }
}

mixin template Finish()
{
    void finish()
    {
        template Types(Var)
        {
            static if (is(Var == VariantN!(_, TL), size_t _, TL...))
                alias Types = TL;
            else
                static assert (0);
        }

        foreach (elem; contents)
        {
            foreach (T; Types!AllowedMembers)
                if (auto p = elem.peek!T)
                {
                    p.finish();

                    enum idx = staticIndexOf!(T, staticMap!(ElementType, typeof(this.tupleof)));
                    alias property = I!(this.tupleof[idx]);

                    property ~= *p;
                }

        }
    }
}

/// Contains the entire definition of one or more related APIs
struct Registry
{
    Required!(AllowedMembers[]) contents;

    alias AllowedMembers =
        Algebraic!(Comment, VendorIDs, Tags, Types, Enums, Commands, Feature, Extensions);

    /// Contains arbitrary text, such as a copyright statement.
    Comment[] _comment;

    /// Defines Khronos vendor IDs.
    /// Described in detail in the “Layers and Extensions” appendix of the
    /// Vulkan Specification.
    VendorID[] _vendorids;

    /// Defines author prefixes used for extensions and layers.
    /// Prefixes are described in detail in the “Layers and Extensions”
    /// appendix of the Vulkan Specification.
    Tag[] _tags;

    /// Defines API types. Usually only one tag is used.
    Type[] _types;

    /// Defines API token names and values. Usually multiple tags are used.
    /// Related groups may be tagged as an enumerated type corresponding
    /// to a <type> tag, and resulting in a C enum declaration. This ability
    /// is heavily used in the Vulkan API.
    Enums[] _enums;

    /// Defines API commands (functions).
    Command[] _commands;

    /// Defines API feature interfaces (API versions, more or less).
    Feature[] _feature;

    /// Defines API extension interfaces. Usually only one tag is used,
    /// wrapping many extensions.
    Extension[] _extensions;

    void finish()
    {
        template Types(Var)
        {
            static if (is(Var == VariantN!(_, TL), size_t _, TL...))
                alias Types = TL;
            else
                static assert (0);
        }

        foreach (elem; contents)
        {
            foreach (T; Types!AllowedMembers)
                if (auto p = elem.peek!T)
                {
                    p.finish();

                    alias property = I!(mixin("_" ~ T.stringof.toLower));

                    static if (is(T == Feature) || is(T == Enums) || is (T == Comment))
                        property ~= *p;
                    else
                        property ~= p.contents;
                }
                 
        }
    }
}

alias I(alias Sym) = Sym;

///
struct Comment
{
    Required!string contents;

    void finish() { }
}

struct VendorIDs
{
    Required!(VendorID[]) contents;

    void finish() { foreach (ref elem; contents) elem.finish(); }
}

struct Tags
{
    Required!(Tag[]) contents;

    void finish() { foreach (ref elem; contents) elem.finish(); }
}

struct Types
{
    Required!(Type[]) contents;

   void finish() { foreach (ref elem; contents) elem.finish(); }
}

struct Commands
{
    Required!(Command[]) contents;

    void finish() { foreach (ref elem; contents) elem.finish(); }
}

struct Extensions
{
    Required!(Extension[]) contents;

    void finish() { foreach (ref elem; contents) elem.finish(); }
}

/// Vendor IDs for physical devices which do not have PCI vendor ID.
struct VendorID
{
    ///
    Required!string name;

    ///
    Required!uint id;

    ///
    Optional!string comment;

    void finish() { }
}

/// Defines each of the reserved author prefixes used by
/// extension and layer authors.
struct Tag
{
    ///
    Required!string name;

    ///
    Required!string author;

    ///
    Required!string contact;

    void finish() { }
}

///
struct Type
{
    /// Another type name this type requires to complete its definition.
    Optional!string requires;

    /// Name of this type (if not defined in the tag body).
    Optional!string name;

    /// An API name (see <feature> below) which specializes this definition
    /// of the named type, so that the same API types may have different
    ///  definitions for e.g. GL ES and GL. This is unlikely to be used in
    /// Vulkan, where a single API supports desktop and mobile devices,
    /// but the functionality is retained.
    Optional!string api;

    /// A string which indicates that this type contains a more complex
    /// structured definition.
    Optional!Category category;

    /// Arbitrary string (unused).
    Optional!string comment;

    /// Notes another type with the handle category that acts as a parent
    /// object for this type.
    @(ValidIf!(type => type.category == Category.Handle))
    Optional!string parent;

    /// Notes that this struct/union is going to be filled in by the API
    /// rather than an application filling it out and passing it to the API.
    @(ValidIf!(type => type.category.among(Category.Struct, Category.Union)))
    Optional!bool returnedonly;

    ///
    Required!(AllowedMembers) contents;

    alias AllowedMembers = Algebraic!(AllowedTypedMembers[], string);

    alias AllowedTypedMembers = Algebraic!(Member, Validity, type, ApiEntry, Name);

    void finish() { }

    //alias TypeRef = Algebraic!(string, Type*);

    // Hack for forward reference bug
    struct type
    {
        Required!string contents;
    }

    enum Category : string
    {
        None = "",
        BaseType = "basetype",
        Bitmask = "bitmask",
        Define = "define",
        Enum = "enum",
        Funcpointer = "funcpointer",
        Group = "group",
        Handle = "handle",
        Include = "include",
        Struct = "struct",
        Union = "union"
    }

    struct Member
    {
        Optional!string len;

        /// Denotes that the member should be externally synchronized when
        /// accessed by Vulkan.
        Optional!bool externsync;

        /// Denotes whether this value can be omitted by providing NULL
        /// (for pointers), VK_NULL_HANDLE (for handles) or 0
        /// (for bitmasks/values)
        Optional!bool optional;

        /// Prevents automatic validity language being generated for the tagged
        /// item. Only suppresses item-specific validity - parenting
        /// issues etc. are still captured.
        Optional!bool noautovalidity;

        Required!(AllowedMembers[]) contents;

        alias AllowedMembers = Algebraic!(type, Name, Enum);

        //enum LenType : string
        //{
        //    Member = "",
        //    NullTerminated = "null-terminated",
        //    PointerToASingleObject = "1",
        //    LatexExpr = "latexmath"
        //}

        // Hack for forward reference bug
        struct Enum
        {
            Required!string contents;
        }
    }
}

///
struct Enums
{
    ///
    Optional!string name;

    ///
    Optional!EnumBlockType type;

    ///
    Optional!int start;

    ///
    Optional!int end;

    ///
    Optional!string vendor;

    ///
    Optional!string comment;

    ///
    Required!(EnumMember[]) contents;

    void finish() {}

    enum EnumBlockType : string
    {
        None = "",
        Enum = "enum",
        Bitmask = "bitmask"
    }    

    alias EnumMember = Algebraic!(Enum, Unused);

    struct Enum
    {    
        ///
        Optional!string value;

        ///
        Optional!uint bitpos;

        ///
        Required!string name;

        ///
        Optional!string api;

        ///
        Optional!EnumMemberType type;

        ///
        Optional!string alias_;

        alias AllowedValueTypes = Algebraic!(long, float, double);

        void finish() { }

        enum EnumMemberType : string
        {
            Uint = "u",
            Ulong = "ull"
        }
    }

    struct Unused
    {
        ///
        Required!int start;

        ///
        Optional!int end;

        ///
        Optional!string vendor;

        ///
        Optional!string comment;
    }
}

///
struct Command
{
    ///  A string identifying the command queues this command can be placed on.
    Optional!(Queue[]) queues;

    /// A string identifying whether the command can be issued only
    /// inside a render pass, only outside a render pass, or both.
    Optional!RenderPass renderpass;

    /// A string identifying the command buffer levels that this command
    /// can be called by.
    Optional!(CmdBufferLevel[]) cmdbufferlevel;

    ///
    Optional!string comment;

    Required!(AllowedMembers[]) contents;

    alias AllowedMembers = Algebraic!(Proto, Param, Validity, Alias,
        Description, ImplicitExternSyncParams);

    void finish() { }

    enum Queue : string
    {
        Graphics = "graphics",
        Compute = "compute",
        SparseBinding = "sparse_binding",
        Transfer = "transfer"        
    }

    enum RenderPass : string
    {
        Inside = "inside",
        Outside = "outside",
        Both = "both",
    }

    enum CmdBufferLevel : string
    {
        primary = "primary",
        secondary = "secondary"
    }

    ///
    struct Proto
    {
        ///
        Required!(AllowedMembers[]) contents;

        alias AllowedMembers = Algebraic!(Name, Type);
    }

    ///
    struct Param
    {
        /// Whether this value can be omitted by providing NULL (for pointers),
        /// VK_NULL_HANDLE (for handles) or 0 (for bitmasks/values).
        Optional!(OptionalParamType[]) optional;

        Optional!bool noautovalidity;

        /// Indicates that this parameter (e.g. the object a handle refers to, or the
        /// contents of an array a pointer refers to) is modified by the command, and is not
        /// protected against modification in multiple app threads. Parameters which do not
        /// have this attribute are assumed to not require external synchronization.
        Optional!string externsync;

        ///
        Required!AllowedMembers contents;

        alias AllowedMembers = Algebraic!(AllowedTypedMembers[], string);
        alias AllowedTypedMembers = Algebraic!(Name, Type);

        enum OptionalParamType : string
        {
            NonOptional = "false",
            Optional = "true",
            Depends = "false,true",
        }
    }

    ///
    struct Alias
    {
    }

    ///
    struct Description
    {
        ///
        Required!string contents;
    }

    ///
    struct ImplicitExternSyncParams
    {
        /// Contains a list of `Param`s each containing Asciidoc source text
        /// describing an object which is not a parameter of the command, but
        /// is related to one, and which also requires external synchronization.
        Required!(Param[]) contents;
    }

}

///
struct Validity
{
    ///
    Required!(Usage[]) contents;

    ///
    struct Usage
    {
        ///
        Required!string contents;
    }
}

///
struct Feature
{
    /// API name this feature is for (see section 3.2), such as vk.
    Required!string api;

    /// Version name, used as the C preprocessor token under which the version’s
    /// interfaces are protected against multiple inclusion. Example: VK_VERSION_1_0
    Required!string name;

    /// Feature version number, usually a string interpreted as majorNumber.minorNumber.
    Required!string number;

    /// An additional preprocessor token used to protect a feature definition.
    /// Usually another feature or extension name. Rarely used, for odd circumstances
    /// where the definition of a feature or extension requires another to be defined first.
    Optional!string protect;

    ///
    Optional!string comment;

    Required!(AllowedMembers[]) contents;

    Require[] _requires;
    Remove[] _removes;

    alias AllowedMembers = Algebraic!(Require, Remove);

    mixin Finish!();
}

///
struct Extension
{
    /// Extension name, following the conventions in the Vulkan Specification.
    /// Example: name="VK_VERSION_1_0".
    Required!string name;

    /// A decimal number which is the registered, unique extension number for name.
    Required!string number;
    
    /// A regular expression, with an implicit ˆ and $ bracketing it, which should
    /// match the api tag of a set of <feature> tags
    Required!string supported;

    /// An additional preprocessor token used to protect an extension definition.
    /// Usually another feature or extension name. Rarely used, for odd circumstances
    /// where the definition of an extension requires another extension or
    /// a header file to be defined first.
    Optional!string protect;

    /// The author name, such as a full company name. If not present, this can be
    /// taken from the corresponding <tag> attribute. However, EXT and other multi-vendor
    /// extensions may not have a well-defined author or contact in the tag.
    Optional!string author;

    /// The contact who registered or is currently responsible for extensions
    /// and layers using the tag, including sufficient contact information to
    /// reach the contact such as individual name together with email address,
    /// Github username, or other contact information.
    /// If not present, this can be taken from the corresponding <tag>
    /// attribute just like author.
    Optional!string contact;

    ///
    Optional!string comment;

    Required!(AllowedMembers[]) contents;

    Require[] _requires;
    Remove[] _removes;

    alias AllowedMembers = Algebraic!(Require, Remove);

    void finish()
    {
        template Types(Var)
        {
            static if (is(Var == VariantN!(_, TL), size_t _, TL...))
                alias Types = TL;
            else
                static assert (0);
        }

        foreach (elem; contents)
        {
            foreach (T; Types!AllowedMembers)
                if (auto p = elem.peek!T)
                {
                    p.finish();

                    enum idx = staticIndexOf!(T, staticMap!(ElementType, typeof(this.tupleof)));
                    alias property = I!(this.tupleof[idx]);

                    property ~= *p;
                }

        }
    }
}

///
struct Name
{
    ///
    Required!string contents;
}

///
struct ApiEntry
{
    ///
    Required!string contents;
}

/// Defines a set of interfaces (types, enumerants and commands) required by a
/// Feature or Extension.
struct Require
{
    /// String name of an API profile. Interfaces in the tag are only required
    /// (or removed) if the specified profile is being generated. If not specified,
    /// interfaces are required (or removed) for all API profiles.
    Optional!string profile;

    ///
    Optional!string comment;

    /// An API name (see section 3.2). Interfaces in the tag are only required
    /// if the specified API is being generated. If not specified, interfaces are
    /// required for all APIs.
    Optional!string api;

    ///
    Required!(AllowedMembers[]) contents;

    Command[] _commands;
    Enums.Enum[] _enums;
    Type[] _types;

    alias AllowedMembers = Algebraic!(Command, Enums.Enum, Type);

    mixin Finish!();
}

/// Defines a set of interfaces removed by a Feature (this is primarily useful
/// for future profiles of an API which may choose to deprecated and/or remove
/// some interfaces - extensions should never remove interfaces,
/// although this usage is allowed by the schema).
struct Remove
{
    /// String name of an API profile. Interfaces in the tag are only required
    /// (or removed) if the specified profile is being generated. If not specified,
    /// interfaces are required (or removed) for all API profiles.
    Optional!string profile;

    ///
    Optional!string comment;

    /// An API name (see section 3.2). Interfaces in the tag are only removed
    /// if the specified API is being generated. If not specified, interfaces are
    /// removed for all APIs.
    Optional!string api;

    ///
    Required!(AllowedMembers[]) contents;

    Command[] _commands;
    Enums.Enum[] _enums;
    Type[] _types;

    alias AllowedMembers = Algebraic!(Command, Enums.Enum, Type);

    mixin Finish!();
}

