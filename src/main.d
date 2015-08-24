import liara.params;
import liara.parser;
import std.algorithm.iteration;
import std.conv;
import std.file;
import std.getopt;
import std.path;
import std.stdio;

enum Format { html, txt }

string baseUrl;
Format format;

int main(string[] args) {
	// Initialize global variables
	baseUrl = getcwd();
	
	// Parse command-line options
	auto opts = getopt(args,
		config.bundling,
		config.caseInsensitive,
		config.passThrough,
		"f|format", "Defines output format for the text. Possible values: html, txt.",       &format,
		"b|base",   "Base URL used for constructing links that are sspecified as relative.", &baseUrl,
	);
	string input  = args.length>1 ? args[1] : "-";
	string output = args.length>2 ? args[2] : "-";
	
	// Show help if asked
	if (opts.helpWanted) {
		defaultGetoptPrinter(
			"Liara, a lightweight markup parser.\nUsage: liara [options...] [input] [output]\n",
			opts.options);
		writeln();
		writeln(
			"Both input and output can be specified as:\n"
			" * a filename: Liara will only process given file;\n"
			" * a directory: Liara will process all *.lr files in the directory, recursively;\n"
			" * \"-\" (default): Liara will process standard input stream as a file.\n"
		);
		writeln(
			"If input is specified as a file or a stream, output must be a file or a stream.\n"
			"If input is specified as a directory, output must be a directory.\n"
		);
		return 0;
	}
	
	try
	{
		// Check that input and output are specified correctly
		if (input == "-") {
			// Input is a stream
			if (output != "-" && (exists(output) && !isFile(output)))
				throw new OutputMustBeFileOrStream;
		}
		else if (isFile(input)) {
			// Input is a file
			if (output != "-" && (exists(output) && !isFile(output)))
				throw new OutputMustBeFileOrStream;
		}
		else {
			// Input is a directory
			if (output == "-" || (exists(output) && !isDir(output)))
				throw new OutputMustBeDirectory;
		}
		
		// Prepare parser parameters
		auto params = new CliParserAdapter;
		
		// Run the parser as many times as needed
		if (input == "-") {
			// Read stdin and parse it
			string inputString;
			while (!stdin.eof)
				inputString ~= stdin.readln();
			performSingleConversion(inputString, output, params);
		}
		else if (isFile(input)) {
			// Read a file and parse it
			string inputString = readText(input);
			performSingleConversion(inputString, output, params);
		}
		else {
			// Iterate all files in given directory and parse them
			foreach (singleInput; dirEntries(input, SpanMode.depth)) {
				if (!isFile(singleInput)) continue;
				
				// Create corresponding subdirectory in the output directory
				auto singleOutputRelative = relativePath(absolutePath(singleInput), absolutePath(input));
				auto singleOutput = buildNormalizedPath(output, singleOutputRelative);
				mkdirRecurse(dirName(singleOutput));
				
				// Choose file extension
				singleOutput = stripExtension(singleOutput) ~ "." ~ format.to!string;
				
				// Perform conversion
				performSingleConversion(readText(singleInput), singleOutput, params);
			}
		}
		
		return 0;
	}
	catch (LException e) {
		stderr.writeln("  ERROR "~e.code.to!string~": "~e.msg);
		return e.code;
	}
}


/**
	Converts a single text to required format.
	Given output must be "-" or a file path, not a directory path.
	The function returns nothing and just writes output to file or stream.
 */
private void performSingleConversion(in string inputString, in string output, CliParserAdapter params) {
	// Perform the parsing
	LiaraResult result = parseLiara(inputString, params);
	
	if (output == "-")
		write(result.htmlOutput);
	else
		std.file.write(output, result.htmlOutput);
}


private class CliParserAdapter: LiaraParams
{
	override Link makeLink(string target, bool needLabel) {
		return new Link(asNormalizedPath(absolutePath(target, baseUrl)).to!string, target);
	}
	
	override string processImageUrl(string url) {
		return url;
	}
	
	override string makeBlock(string pluginName, string input, bool addLast, LiaraResult* r) {
		return "";
	}
}


//////////////////////////////////////////////////
// Exceptions

abstract class LException: Exception
{
	immutable int code;
	
	this(int code, string msg) {
		this.code = code;
		super(msg);
	}
}

class LE(int _code, string _message): LException
{
	this() {
		super(_code, _message);
	}
}

class OutputMustBeFileOrStream: LE!(1, "When input is file or stream, output must be file or stream, too.") {}
class OutputMustBeDirectory:    LE!(2, "When input is a directory, output must be a directory, too.") {}
class InputNotExists:           LE!(3, "Can't find input file or directory.") {}