
import std.meta, std.traits;
import std.functional : unaryFun;
import std.range : ElementType;

enum isType(T) = isInstanceOf!(Type, T);
enum isTypeTuple(T) = isInstanceOf!(TypeTuple, T);

auto type(T)()
{
    return Type!T.init;
}

auto typeTuple(Types...)(Types)
{
    return TypeTuple!Types();
}

struct Type(T)
{
    alias type = T;
    //alias Type = T;

    auto opSlice()()
    { return Type!(T[]).init; }

    auto opIndex(K)(K keyType) if (isType!K)
    { return Type!(T[keyType.type]).init; }

    auto constOf()()
    { return Type!(const(T)).init; }

    auto immutableOf()()
    { return Type!(immutable(T)).init; }

    auto sharedOf()()
    { return Type!(shared(T)).init; }

    string toString()
    {
        return "Type!("~T.stringof~")";
    }
}

struct TypeTuple(Types...)
{
    //pragma (msg, "TT:", Types);

    import std.meta: allSatisfy;
    static assert(allSatisfy!(isType, Types), "Variadic parameters need to be of type 'Type!'");

    enum empty = Types.length == 0;

    static if (empty)
    {
        // Special case allowing 
        // ElementType!(typeof(this)) == TypeTuple!()
        // in generic code.

        auto front()() { return this; }
        auto back()() { return this; }
        auto dropOne()() { return this; }
        auto dropBackOne()() { return this; }
    }
    else
    {
        auto front()() { return this[0]; }
        auto back()() { return this[$ - 1]; }
        auto dropOne()() { return TypeTuple!(Types[1 .. $]).init; }
        auto dropBackOne()() { return TypeTuple!(Types[0 .. $ - 1]).init; }
    }   

    Types expand;
    alias expand this;
    alias Type = Types;

    string toString()
    {
        import std.range;

        string[] s;
        foreach(t; expand)
            s ~= t.toString();

        return "TypeTuple!(" ~ s.join(", ") ~")";
    }
}

auto append(T, TT)(TT tuple, T type)
{
    //pragma (msg, "append:", TT, T);
    return TypeTuple!(tuple.Type, T)();
}

struct Transducer(Input, Output = Input)
{

}

unittest
{
    Transducer!int filter_odd = filter2((int x) => x % 2);

    Transducer!(int, string) serialize = map((int x) => "int" );
}

struct Lambda11886(alias fun, State...)
{
    static if (State.length)
    {
        @disable this();
        this (State s) { this.state = s; }
    }
    
    State state;
    auto opCall(A...)(A args)
    {
        return fun(state, args);
    }
}

auto λ(alias fun, State...)(State state)
{
    static if (State.length)
        return Lambda11886!(fun, State)(state);
    else
        return Lambda11886!(fun).init;
}

auto accumulate(Rf, S, In, size_t line = __LINE__)(In input, Rf step, S state)
    if ( is(ElementType!In E))
{
    pragma (msg, line.stringof ~ " accumulate: S(", typeof(S.init), "), E(", typeof(ElementType!In.init), ") ");

    static if (__traits(compiles, { enum len = input.length; }))
    {
        static if (input.length == 0)
            return state;
        else
            return step(accumulate(input.dropBackOne, state, step), input.back);
    }
    else
    {
        foreach (elem; input)
            state = step(state, elem);

        return state;
    }
}

alias filter2 = (pred) {
    return λ!(
        (pred1, step)
        {
            return λ!(
                (pred2, step1, s, ins)
                {
                    static if (__traits(compiles, { enum len = pred2(ins); }))
                    {
                        static if (pred2(ins))
                            return step1(s, ins);
                        else
                            s;
                    }
                    else
                    {
                        return pred2(ins)? step1(s, ins) : s;
                    }
                }
                )(pred1, step);
        }
        )(pred);
};

alias map2 = (fn) {
    return λ!(
        (fn1, step)
        {
            return λ!(
                (step1, fn2, s, ins)
                {
                    return step1(s, fn2(ins));
                }
            )(step, fn1);
        }
    )(fn);
};

auto outputRf = λ!((output, input)
{
    import std.range : put;
    output.put(input);
    return output;
});

void testComposition()
{
    auto arr1 = [4, 2, 7, 4, 6, 5, 1];

    auto filter = filter2(λ!(x => x%2 == 0));
}

void testMapWithArray()
{
    import std.stdio;
    import std.range : iota;

    auto arr1 = [4, 2, 7, 4, 6, 5, 1];
    auto arr2 = new int[arr1.length];

    alias transform = (input, output, fn) =>
        input.accumulate(map2(fn)(outputRf), output);

    transform(arr1, arr2, λ!(x => x * 2));
    writeln(arr2);

    assert (1.iota(4).accumulate(λ!((a, b) => a + b), 0) == 6);
    assert (1.iota(5).accumulate(λ!((a, b) => a * b), 1) == 24);
    assert (["I", "am", "one"].accumulate(λ!((a, b) => a ~ b ~ " " ), "") == "I am one ");

    //auto rangeWrapperRf = λ!((state, input)
    //{
    //    import std.range : put;
    //    output.put(input);
    //    return output;
    //});
    //
    //alias sequence = (input, xform) =>
    //    input.accumulate(xform(outputRf), output);
    //
    //writeln(transform([1, 2, 3], map2((int x) => x + 1)));
} 

void testMapWithTypes()
{
    import std.stdio;

    auto tuple = TypeTuple!(Type!int, Type!double, Type!char)();

    auto trf = λ!( (state, input) => state.append(input) );

    //alias transform = (input, xform) =>
   //     input.accumulate(xform(trf), typeTuple());

    //auto result = transform(tuple, map2( λ!( t => t[] )));
    //writeln(result);
}

void main()
{
    testMapWithArray();
    testMapWithTypes();
    return;


    //int n = 10;
    //import std.stdio;

    //auto p = tupleFromTypes!(int, double, byte[]);

    //writeln(p);
    //writeln(p.front);
    //writeln(p.popFront.popFront.popFront.empty);

    //static bool always(bool x) { return x; }

    //auto reducer()
    //{
    //    struct Reducer { auto opCall(State, Input)(State s, Input tuple) { return tuple.popFront(); } }
    //    return Reducer.init;
    //}

    //enum passThrough = map!((x) { pragma (msg, typeof(x)); return Type!int(); });
    //enum result = passThrough(reducer());

    ////auto a = result(p);

    ////enum r = result(p, true);

    //writeln(result(0, p));


    //foreach (elem; filter!(x => true)(p))
    //    writeln(elem);

}

//import std.stdio, std.algorithm, std.range;
//
//import arsd.dom;
//import vulkan.registry;
//
//enum SpanMode
//{
//    depthFirst,
//    breadthFrist
//}
//
//enum Order
//{
//    preOrder,
//    inOrder,
//    postOrder
//}
//
//struct TreeVisitor(alias visitFunc, Order order, SpanMode span, Document = arsd.dom.Document, alias getChildren)
//    if (true)   
//{
//    Document parentNode;
//    Document currentNode;
//
//    void visitPreOrder(Document node)
//    {
//        visitPreOrder(node);
//        foreach (elem; getChildren(node))
//            visitPreOrder(elem);
//    }
//
//    void visitPostOrder(Document node)
//    {        
//        foreach (elem; getChildren(node))
//            visitPostOrder(elem);
//
//        visitPostOrder(node);
//    }
//
//    void visitInOrder(Document node)
//    {        
//        auto c = getChildren(node);
//
//        visitInOrder(c[0]);
//        visitInOrder(node);
//        visitInOrder(c[1]);
//    }
//
//    void visitLevelOrder(Document node)
//    {        
//        foreach (elem; getChildren(node))
//            visitPostOrder(elem);
//
//        visitPostOrder(node);
//    }
//}
//
//void main()
//{
//    auto str = cast(string)std.file.read("./data/vk.xml");
//    auto doc = new arsd.dom.Document(str);
//    //auto r = doc.root.deserialize!Registry;
//    //r.finish();
//    //writeln("Done!");
//
//    writeln(doc.root.childNodes.filter!(n => n.tagName != "#text" ).drop(1).front.tagName);
//
//    readln();
//    //r.dump.writeln;
//}
//
//enum hasToString(T) = is(typeof(T.init.toString()) : string);
//
//string dump(uint level = 0, T)(T val)
//{
//    import std.traits, std.variant, std.range, std.array, std.conv, std.format;
//
//    enum level1 = level + 1;
//    enum string indent1 = ' '.repeat(level * 4).array;
//    enum string indent2 = ' '.repeat((level + 1) * 4).array;
//
//    static if (isScalarType!T || is(T : const(char)[]) || is(T == enum))
//    {
//        return val.to!string;
//    }
//    else static if (is(T == MyNullable!X, X))
//    {
//        if (val.isNull)
//            return "Nullable.null";
//        else
//            return dump!level1(val.val);
//    }
//    else static if (is(T == VariantN!(_, TL), size_t _, TL...))
//    {
//        foreach (Type; TL)
//            if (auto var = val.peek!Type)
//                return dump!level1(*var);
//
//        return "ERROR!!!";
//    }
//    else static if (is(T == E[], E))
//    {
//        string result = indent1 ~ T.stringof ~ "\n";
//
//        foreach (elem; val)
//            result ~= dump!level1(elem);
//
//        return result;
//    }
//    else static if (is(T == K[V], K, V))
//    {
//        // ignore
//        return "";
//    }
//    else static if (is(T == struct))
//    {
//        static if (val.tupleof.length == 1 && T.tupleof[0].stringof == "contents")
//        {
//            return format("%s %s {%s}: %s\n",
//                             indent1,
//                             T.stringof,
//                             typeof(T.contents).stringof,
//                             dump(val.contents));
//        }
//        else
//        {
//            string result = indent1 ~ T.stringof ~ "\n";
//
//            foreach (idx, _; val.tupleof)
//            {
//                alias Type = typeof(T.tupleof[idx]);
//                string type__ = Type.stringof;
//                string name__ = T.tupleof[idx].stringof;
//
//                static if (isScalarType!Type || is(Type == string) || is(Type == enum) || is(Type == MyNullable!Y, Y))
//                {
//                    static if (is(Type == MyNullable!X, X))
//                    {
//                        if (val.tupleof[idx].isNull) continue;
//                    }
//
//                    result ~= format("%s%s {%s}: %s\n", indent2, T.tupleof[idx].stringof, typeof(T.tupleof[idx]).stringof, dump(val.tupleof[idx]));
//                }
//                else
//                {
//                    result ~= dump!level1(val.tupleof[idx]);
//                }
//            }
//
//            return result;
//        }
//    }
//    else
//        static assert (0, "Unhandled type: " ~ T.stringof ~ "!");
//}
