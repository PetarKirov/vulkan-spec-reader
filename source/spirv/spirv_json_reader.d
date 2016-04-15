module spirv_json_to_d_gen;

import std.algorithm : map, sort, joiner, splitter;
import std.array : array, byPair;
import std.format : format;
import std.file : readText;
import std.json : parseJSON;
import std.stdio : writefln;
import std.typecons : tuple;
import std.conv : to;

string generateDheaderFromSpirvJson(string filename = "spirv.json")
{
	auto json = filename.readText.parseJSON;
    string result;

	foreach (paragraph; json["spv"]["meta"]["Comment"].array[0 .. $ - 2])
		result ~= format("%s\n", paragraph.array
			.map!(
				a => a.str.splitter('\n').map!q{"// " ~ a}.joiner("\n")
			).joiner("\n"));

	result ~= format(q{enum SPV_VERSION = 0x10000;});
	result ~= format(q{enum SPV_REVISION = 3;});
    result ~= format("");
	result ~= format(q{alias Id = uint;});
    result ~= format("");

	foreach (key, value; json["spv"]["meta"].object)
	{
		if (key != "Comment")
			result ~= format("enum uint %s = %s;", key, value);
	}

	result ~= format("");

	foreach (enumeration; json["spv"]["enum"].array)
	{
		if (enumeration["Type"].str == "Value")
		{
			result ~= format("enum %s : Id\n{", enumeration["Name"].str);

			result ~= format("%-(    %s,\n%)", enumeration["Values"]
				.object.byPair
				.map!(pair => tuple(pair[0], pair[1].integer))
				.array.sort!"a[1] < b[1]"
				.map!(x => "%s = %s".format(x[0], x[1])));

			writefln("}\n");
		}
		else if (enumeration["Type"].str == "Bit")
		{
			foreach (idx, str; ["Shift", "Mask"])
			{
				result ~= format("enum %s : uint\n{", enumeration["Name"].str ~ str);

				if (idx) result ~= format("    MaskNone = 0,");

				result ~= format("%-(    %s,\n%)", enumeration["Values"].object.byPair
					.map!(pair => tuple(pair[0], pair[1].integer))
					.array.sort!"a[1] < b[1]"
					.map!(x => "%s = %s".format(x[0], idx? 1 << x[1] : x[1])));

				result ~= format("}\n");
			}
		}
		else
			assert (0, "Unsupported enum type: " ~ enumeration["Type"].str);
	}

    return result;
}
