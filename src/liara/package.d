module liara;

import core.memory;
import liara.nodes;
import liara.params;
import liara.runtime;
import std.algorithm;
import std.array;
import std.conv;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;
import std.typetuple;
import std.xml;
public import pegged.grammar;

mixin(grammar(import("liara.peg")));


/// Standard parsing result.
class LiaraResult {
	string htmlOutput;
	string plainOutput;
}

/// Same as LiaraResult, but also includes ParseTree. For debugging purposes.
class LiaraResultExtended: LiaraResult {
	ParseTree tree;
}



/**
	The public interface to the parser.
	
	Prepares the parse tree (it will call aux functions like prepare_BeginCut() where required)
	and then process the tree with processNode().
 */
T parseLiara(T=LiaraResult)(in string input, LiaraParams params)
if (is(T : LiaraResult)) {
	parserParams = params;
	
	// Run first pass
	ParseTree tree = Liara(input);
	
	// Run second pass
	T result = new T();
	result.htmlOutput  = processNode!true(tree);
	result.plainOutput = processNode!false(tree);
	static if (is(T == LiaraResultExtended)) {
		result.tree = tree;
	}
	
	// Reset counters, free memory
	rt.allCuts = [];
	rt.cutsStack = [];
	rt.cutsJustOpened = [];
	rt.cutsJustClosed = [];
	rt.cutIndex = 0;
	rt.numOfBlockquotesOpenedByLine = rt.numOfBlockquotesOpenedByLine.init;
	rt.numOfBlockquotesClosedByLine = rt.numOfBlockquotesClosedByLine.init;
	rt.quotationLevels = rt.quotationLevels.init;
	GC.collect();
	
	return result;
}

/// Shortcut for getting only text result of parsing.
T parseLiara(T)(in string input, LiaraParams params)
if (is(T == string)) {
	return params.makeHtml
		? parseLiara!LiaraResult(input, params).htmlOutput
		: parseLiara!LiaraResult(input, params).plainOutput;
}


package string parseAll(bool htmlMode)(ParseTree[] nodes) {
	string result;
	foreach (node; nodes)
		result ~= processNode!htmlMode(node);
	return result;
}


/// Aux method. Don't use it directly.
ParseTree prepare_Block(ParseTree)(ParseTree p) {
	if (!p.successful) return p;
	
	// 1. Update information about already existing cuts, newly opened cuts, closed cuts.
	// (Fortunately, CutInfo.addBlock(p) will ignore duplicated calls with same blocks.)
	foreach (CutInfo cut; rt.cutsStack) {
		CuttedBlock block = cut.addBlock(p);
		if (!rt.cutsJustOpened.canFind(cut))
			block.fromTheBeginning = true;
		if (!rt.cutsJustClosed.canFind(cut))
			block.toTheEnd = true;
	}
	foreach (cut; rt.cutsJustOpened) {
		CuttedBlock block = cut.addBlock(p);
		if (!rt.cutsJustClosed.canFind(cut))
			block.toTheEnd = true;
	}
	foreach (cut; rt.cutsJustClosed) {
		CuttedBlock block = cut.addBlock(p);
		if (!rt.cutsJustOpened.canFind(cut))
			block.fromTheBeginning = true;
	}
	
	// Clear the queues for future usage
	rt.cutsJustOpened = [];
	rt.cutsJustClosed = [];
	
	// 2. Check if the block starts with a BeginCut node.
	// In fact, it may start with several cuts: «(((CUT))) (((CUT))) (((CUT))) Text...»,
	// so we iterate through as many first nodes as needed.
	// Note that a node is not BeginCut, it is option!(Liara.BeginCut), so we look a level deeper.
	foreach (node; p.children)
		if (node.children.length && node.children[0].name == "Liara.BeginCut") {
			ParseTree c = node.children[0];
			rt.cutsByBeginIndex[c.begin].addBlock(p).fromTheBeginning = true;
		}
		else
			break; // There is no more cut beginnings here
	
	// 3. Check if the block ends with an EndCut node.
	// To do so, iterate through all last nodes that are EndCuts: «...Text (((/CUT))) (((/CUT))) (((/CUT)))».
	// Technically, we iterate through them in incorrect order, since (in user's mind) the last EndCut
	// should close the first BeginCut, not the last BeginCut. But it does not influence on anything here,
	// because all the iterated nodes are siblings, and we may walk them in any order.
	foreach_reverse (node; p.children) {
		if (node.children.length && node.children[0].name == "Liara.EndCut") {
			ParseTree c = node.children[0];
			if (c.end in rt.cutsByEndIndex) { // if it's not an abandoned EndCut (without BeginCut)
				rt.cutsByEndIndex[c.end].addBlock(p).toTheEnd = true;
			}
		}
		else
			break; // There is no more cut endings here
	}
	
	// 4. Check if the current block begins or previous block ends a blockquote.
	// For this purpose, we store the previous block's quotation level (number of ">"s in it)
	// and compare with the current block's quotation level.
	// If the current level is deeper, that means that current line opens some quotes.
	// If the current level is less deep, that means that previous line closed some quotes.
	size_t oldLevel = rt.quotationLevels.get(rt.lastBlockBegin, 0);
	size_t newLevel = (p.children.length && p.children[0].name == "zeroOrMore!(Liara.QuotationMark)")
		? p.children[0].children.length
		: 0;
	if (newLevel > oldLevel)
		rt.numOfBlockquotesOpenedByLine[p.begin] = newLevel - oldLevel;
	else if (newLevel < oldLevel)
		rt.numOfBlockquotesClosedByLine[rt.lastBlockBegin] = oldLevel - newLevel;
	
	// Update the variables for use in future
	rt.lastBlockBegin = p.begin;
	rt.quotationLevels[p.begin] = newLevel;
	
	return p;
}


/// Aux method. Don't use it directly.
ParseTree prepare_BeginCut(ParseTree)(ParseTree p) {
	if (!p.successful) return p;
	
	//// Create new cut object
	string id = "cut-"~(rt.cutIndex++).to!string;
	string label = p.children.length>1 ? p.children[1].matches[0] : "Читать дальше »";
	auto cut = new CutInfo(id, label);
	
	// Append the cut to arrays
	rt.allCuts ~= cut;                  // to be able to iterate through all the cuts
	rt.cutsStack ~= cut;                // to remember which cut should be closed in endCut()
	rt.cutsByBeginIndex[p.begin] = cut; // to remember which CutInfo was opened here
	rt.cutsJustOpened ~= cut;           // to add current block to cut.blocks
	
	return p;
}


/// Aux method. Don't use it directly.
ParseTree prepare_EndCut(ParseTree)(ParseTree p) {
	if (!p.successful) return p;
	
	// Close latest opened cut
	if (!rt.cutsStack.empty) {
		rt.cutsByEndIndex[p.end] = rt.cutsStack.back;
		rt.cutsJustClosed ~= rt.cutsStack.back;
		rt.cutsStack.popBack();
	}
	
	return p;
}


/**
	Exception to be thrown when an unknown plugin name is used.
 */
class UnsupportedPluginException: Exception
{
	immutable string pluginName;
	
	this(in string pluginName) {
		this.pluginName = pluginName;
		super("Unsupported plugin: "~pluginName);
	}
}