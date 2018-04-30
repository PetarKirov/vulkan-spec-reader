import std.meta, std.traits;
import std.functional : unaryFun;
import std.range : ElementType;

import std.stdio, std.algorithm, std.range;

import arsd.dom;
import vulkan.registry;

enum SpanMode
{
    depthFirst,
    breadthFrist
}

enum Order
{
    preOrder,
    inOrder,
    postOrder
}

struct TreeVisitor(alias visitFunc, Order order, SpanMode span, Document = arsd.dom.Document, alias getChildren)
    if (true)
{
    Document parentNode;
    Document currentNode;

    void visitPreOrder(Document node)
    {
        visitPreOrder(node);
        foreach (elem; getChildren(node))
            visitPreOrder(elem);
    }

    void visitPostOrder(Document node)
    {
        foreach (elem; getChildren(node))
            visitPostOrder(elem);

        visitPostOrder(node);
    }

    void visitInOrder(Document node)
    {
        auto c = getChildren(node);

        visitInOrder(c[0]);
        visitInOrder(node);
        visitInOrder(c[1]);
    }

    void visitLevelOrder(Document node)
    {
        foreach (elem; getChildren(node))
            visitPostOrder(elem);

        visitPostOrder(node);
    }
}

void main()
{
    auto str = cast(string)std.file.read("./data/vk.xml");
    auto doc = new arsd.dom.Document(str);
    auto r = doc.root.deserialize!Registry;
    r.finish();
    writeln("Done!");

    //writeln(doc.root.childNodes.filter!(n => n.tagName != "#text" ).drop(1).front.tagName);

    readln();
    r.dump.writeln;
}

enum hasToString(T) = is(typeof(T.init.toString()) : string);

string dump(uint level = 0, T)(T val)
{
    import std.traits, std.variant, std.range, std.array, std.conv, std.format;

    enum level1 = level + 1;
    enum string indent1 = ' '.repeat(level * 4).array;
    enum string indent2 = ' '.repeat((level + 1) * 4).array;

    static if (isScalarType!T || is(T : const(char)[]) || is(T == enum))
    {
        return val.to!string;
    }
    else static if (is(T == MyNullable!X, X))
    {
        if (val.isNull)
            return "Nullable.null";
        else
            return dump!level1(val.val);
    }
    else static if (is(T == VariantN!(_, TL), size_t _, TL...))
    {
        foreach (Type; TL)
            if (auto var = val.peek!Type)
                return dump!level1(*var);

        return "ERROR!!!";
    }
    else static if (is(T == E[], E))
    {
        string result = indent1 ~ T.stringof ~ "\n";

        foreach (elem; val)
            result ~= dump!level1(elem);

        return result;
    }
    else static if (is(T == K[V], K, V))
    {
        // ignore
        return "";
    }
    else static if (is(T == struct))
    {
        static if (val.tupleof.length == 1 && T.tupleof[0].stringof == "contents")
        {
            return format("%s %s {%s}: %s\n",
                             indent1,
                             T.stringof,
                             typeof(T.contents).stringof,
                             dump(val.contents));
        }
        else
        {
            string result = indent1 ~ T.stringof ~ "\n";

            foreach (idx, _; val.tupleof)
            {
                alias Type = typeof(T.tupleof[idx]);
                string type__ = Type.stringof;
                string name__ = T.tupleof[idx].stringof;

                static if (isScalarType!Type || is(Type == string) || is(Type == enum) || is(Type == MyNullable!Y, Y))
                {
                    static if (is(Type == MyNullable!X, X))
                    {
                        if (val.tupleof[idx].isNull) continue;
                    }

                    result ~= format("%s%s {%s}: %s\n", indent2, T.tupleof[idx].stringof, typeof(T.tupleof[idx]).stringof, dump(val.tupleof[idx]));
                }
                else
                {
                    result ~= dump!level1(val.tupleof[idx]);
                }
            }

            return result;
        }
    }
    else
        static assert (0, "Unhandled type: " ~ T.stringof ~ "!");
}
