module liara;

import core.memory;
import liara.nodes;
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
public import liara.params;

mixin(grammar(import("liara.peg")));

// We use special compile-time function to convert symbols back to string,
// so that instead of «case "Link"» we could write «case S!(Liara.Link)».
// This is longer, but this allows to detect mistypes in cases.
string S(alias symbol)() {
	return __traits(identifier, symbol);
}

/// Standard parsing result.
class LiaraResult {
	string htmlOutput;
	string plainOutput;
}

/// Same as LiaraResult, but also includes ParseTree. For debugging purposes.
class LiaraResultExtended: LiaraResult {
	ParseTree tree;
}


/// Runtime parameters set by user when calling parser.
package LiaraParams parserParams;


// -----------------------------------------------------------
//
// Variables to serve cuts parsing.
//
// -----------------------------------------------------------

/// All the cuts.
package CutInfo[] allCuts;

/// Temporary stack for cuts currently opened.
/// It grows when a new cut is opened and decreases when it is closed.
/// This stack is being used by Semantic Actions while building the ParseTree.
package CutInfo[] cutsStack;

/// Cuts indexed by position of its opening and closed tags.
package CutInfo[size_t] cutsByBeginIndex;
package CutInfo[size_t] cutsByEndIndex;

/// Cuts counter.
/// This is used in first pass for creating incremented IDs
/// and for getting the cuts back in second pass.
package ulong cutIndex;

/// List of cuts that were opened and closed in current block.
/// Appended each time we see a BeginCut/EndCut; read and flushed each time we finish a block.
package CutInfo[] cutsJustOpened;
package CutInfo[] cutsJustClosed;

/// Lists of cuts needed to be opened/closed at the end of current block.
/// Used in «case Paragraph» and «case Block».
package CutInfo[] inlineCutsToOpen;
package CutInfo[] blockCutsToOpen;
package CutInfo[] inlineCutsToClose;
package CutInfo[] blockCutsToClose;

/// True while processing first block
package bool isCurrentBlockFirst = true;

/// Index of beginning of latest opened block during first pass
package size_t lastBlockBegin;

// -----------------------------------------------------------



// -----------------------------------------------------------
//
// Variables to serve blockquotes parsing.
//
// -----------------------------------------------------------

/// Quotation level of every block
package size_t[size_t] quotationLevels;

/// Numbers of blockquotes that should be opened/closed with the Line with given p.begin.
package size_t[size_t] numOfBlockquotesOpenedByLine;
package size_t[size_t] numOfBlockquotesClosedByLine;

// -----------------------------------------------------------



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
	allCuts = [];
	cutsStack = [];
	cutsJustOpened = [];
	cutsJustClosed = [];
	cutIndex = 0;
	isCurrentBlockFirst = true;
	numOfBlockquotesOpenedByLine = numOfBlockquotesOpenedByLine.init;
	numOfBlockquotesClosedByLine = numOfBlockquotesClosedByLine.init;
	quotationLevels = quotationLevels.init;
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
	foreach (CutInfo cut; cutsStack) {
		CuttedBlock block = cut.addBlock(p);
		if (!cutsJustOpened.canFind(cut))
			block.fromTheBeginning = true;
		if (!cutsJustClosed.canFind(cut))
			block.toTheEnd = true;
	}
	foreach (cut; cutsJustOpened) {
		CuttedBlock block = cut.addBlock(p);
		if (!cutsJustClosed.canFind(cut))
			block.toTheEnd = true;
	}
	foreach (cut; cutsJustClosed) {
		CuttedBlock block = cut.addBlock(p);
		if (!cutsJustOpened.canFind(cut))
			block.fromTheBeginning = true;
	}
	
	// Clear the queues for future usage
	cutsJustOpened = [];
	cutsJustClosed = [];
	
	// 2. Check if the block starts with a BeginCut node.
	// In fact, it may start with several cuts: «(((CUT))) (((CUT))) (((CUT))) Text...»,
	// so we iterate through as many first nodes as needed.
	// Note that a node is not BeginCut, it is option!(Liara.BeginCut), so we look a level deeper.
	foreach (node; p.children)
		if (node.children.length && node.children[0].name == "Liara.BeginCut") {
			ParseTree c = node.children[0];
			cutsByBeginIndex[c.begin].addBlock(p).fromTheBeginning = true;
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
			if (c.end in cutsByEndIndex) { // if it's not an abandoned EndCut (without BeginCut)
				cutsByEndIndex[c.end].addBlock(p).toTheEnd = true;
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
	size_t oldLevel = quotationLevels.get(lastBlockBegin, 0);
	size_t newLevel = (p.children.length && p.children[0].name == "zeroOrMore!(Liara.QuotationMark)")
		? p.children[0].children.length
		: 0;
	if (newLevel > oldLevel)
		numOfBlockquotesOpenedByLine[p.begin] = newLevel - oldLevel;
	else if (newLevel < oldLevel)
		numOfBlockquotesClosedByLine[lastBlockBegin] = oldLevel - newLevel;
	// Update the variables for use in future
	lastBlockBegin = p.begin;
	quotationLevels[p.begin] = newLevel;
	
	// 5. After any block, remember that further blocks can't influence on post's header
	isCurrentBlockFirst = false;
	lastBlockBegin = p.begin;
	
	return p;
}


/// Aux method. Don't use it directly.
ParseTree prepare_BeginCut(ParseTree)(ParseTree p) {
	if (!p.successful) return p;
	
	//// Create new cut object
	string id = "cut-"~(cutIndex++).to!string;
	string label = p.children.length>1 ? p.children[1].matches[0] : "Читать дальше »";
	auto cut = new CutInfo(id, label);
	
	// Append the cut to arrays
	allCuts ~= cut;                  // to be able to iterate through all the cuts
	cutsStack ~= cut;                // to remember which cut should be closed in endCut()
	cutsByBeginIndex[p.begin] = cut; // to remember which CutInfo was opened here
	cutsJustOpened ~= cut;           // to add current block to cut.blocks
	
	return p;
}


/// Aux method. Don't use it directly.
ParseTree prepare_EndCut(ParseTree)(ParseTree p) {
	if (!p.successful) return p;
	
	// Close latest opened cut
	if (!cutsStack.empty) {
		cutsByEndIndex[p.end] = cutsStack.back;
		cutsJustClosed ~= cutsStack.back;
		cutsStack.popBack();
	}
	
	return p;
}