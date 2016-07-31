module liara.parser;

import core.memory;
import liara.cutinfo;
import liara.params;
import pegged.grammar;
import std.algorithm;
import std.array;
import std.conv;
import std.regex;
import std.stdio;
import std.string;
import std.typecons;
import std.typetuple;
import std.xml;

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
private LiaraParams parserParams;


// -----------------------------------------------------------
//
// Variables to serve cuts parsing.
//
// -----------------------------------------------------------

/// All the cuts.
private CutInfo[] allCuts;

/// Temporary stack for cuts currently opened.
/// It grows when a new cut is opened and decreases when it is closed.
/// This stack is being used by Semantic Actions while building the ParseTree.
private CutInfo[] cutsStack;

/// Cuts indexed by position of its opening and closed tags.
private CutInfo[size_t] cutsByBeginIndex;
private CutInfo[size_t] cutsByEndIndex;

/// Cuts counter.
/// This is used in first pass for creating incremented IDs
/// and for getting the cuts back in second pass.
private ulong cutIndex;

/// List of cuts that were opened and closed in current block.
/// Appended each time we see a BeginCut/EndCut; read and flushed each time we finish a block.
private CutInfo[] cutsJustOpened;
private CutInfo[] cutsJustClosed;

/// Lists of cuts needed to be opened/closed at the end of current block.
/// Used in «case Paragraph» and «case Block».
private CutInfo[] inlineCutsToOpen;
private CutInfo[] blockCutsToOpen;
private CutInfo[] inlineCutsToClose;
private CutInfo[] blockCutsToClose;

/// True while processing first block
private bool isCurrentBlockFirst = true;

/// Index of beginning of latest opened block during first pass
private size_t lastBlockBegin;

// -----------------------------------------------------------



// -----------------------------------------------------------
//
// Variables to serve blockquotes parsing.
//
// -----------------------------------------------------------

/// Quotation level of every block
private size_t[size_t] quotationLevels;

/// Numbers of blockquotes that should be opened/closed with the Line with given p.begin.
private size_t[size_t] numOfBlockquotesOpenedByLine;
private size_t[size_t] numOfBlockquotesClosedByLine;

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


/**
	Process a node of the parse tree.
	
	Initially it is called from parseLiara() for the entire tree and recursively calls itself for its nodes.
 */
private string processNode(bool htmlMode)(ParseTree p) {
	switch (p.name) {
		case "Liara.AutoUrl":       return processNode__AutoUrl!htmlMode(p);
		case "Liara.BasicChar":     return processNode__BasicChar!htmlMode(p);
		case "Liara.BeginCut":      return processNode__BeginCut!htmlMode(p);
		case "Liara.Block":         return processNode__Block!htmlMode(p);
		case "Liara.BlockImage":    return processNode__BlockImage!htmlMode(p);
		case "Liara.Bold":          return processNode__Bold!htmlMode(p);
		case "Liara.Code":          return processNode__Code!htmlMode(p);
		case "Liara.CustomBlock":   return processNode__CustomBlock!htmlMode(p);
		case "Liara.Del":           return processNode__Del!htmlMode(p);
		case "Liara.EndCut":        return processNode__EndCut!htmlMode(p);
		case "Liara.Heading":       return processNode__Heading!htmlMode(p);
		case "Liara.Italic":        return processNode__Italic!htmlMode(p);
		case "Liara.Line":          return processNode__Line!htmlMode(p);
		case "Liara.Link":          return processNode__Link!htmlMode(p);
		case "Liara.NewLine":       return processNode__NewLine!htmlMode(p);
		case "Liara.NoFormat":      return processNode__NoFormat!htmlMode(p);
		case "Liara.Paragraph":     return processNode__Paragraph!htmlMode(p);
		case "Liara.PlainChar":     return processNode__PlainChar!htmlMode(p);
		case "Liara.Pre":           return processNode__Pre!htmlMode(p);
		case "Liara.QuotationMark": return processNode__QuotationMark!htmlMode(p);
		case "Liara.Ruler":         return processNode__Ruler!htmlMode(p);
		case "Liara.Text":          return processNode__Text!htmlMode(p);
		default: return parseAll!htmlMode(p.children);
	}
}


private string processNode__Text(bool htmlMode)(ParseTree p) {
	isCurrentBlockFirst = true;
	return parseAll!htmlMode(p.children);
}


private string processNode__Paragraph(bool htmlMode)(ParseTree p) {
	string content = parseAll!htmlMode(p.children);
	if (!content.length) return "";
	
	static if (!htmlMode) {
		return content ~ "\n\n";
	}
	else {
		string result = (parserParams.addClassLast && p.begin == lastBlockBegin)
			? "<p class=\"last\">"
			: "<p>";
		
		foreach (cut; allCuts) {
			CuttedBlock currBlock = cut.findBlock(p);
			if (currBlock && currBlock.fromTheBeginning && !currBlock.toTheEnd) {
				if (currBlock.begin == cut.blocks[0].begin)
					result ~= "<span class=\"cut\">"~cut.label~"</span>";
				result ~= "<span class=\"undercut\">";
			}
		}
		
		result ~= content;
		
		// Find if there are cuts that have been opened inside current block
		// and should be closed with </span> here (while continued as <span> or <div> later)
		foreach (cut; inlineCutsToClose)
			result ~= "</span>";
		
		result ~= "</p>\n\n";
		return result;
	}
}


private string processNode__Line(bool htmlMode)(ParseTree p) {
	return parseAll!htmlMode(p.children).strip();
}


private string processNode__PlainChar(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


private string processNode__BasicChar(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


private string processNode__NoFormat(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


private string processNode__AutoUrl(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<a href="`~encode(p.matches[0])~`">`~encode(p.matches[0])~`</a>`
		: p.matches[0];
}


private string processNode__Link(bool htmlMode)(ParseTree p) {
	// A link to any target, either local or global, with an optional label.
	// It is up to user-defined code to convert given target string to valid URL.
	// Sometimes user-defined code can also generate label for given target.
	
	bool needLabel = (p.matches.length == 1);
	if (!htmlMode && !needLabel) {
		// When we have no need to get URL and we have title, just show the title
		return parseAll!false(p.children);
	}
	else {
		Link link = parserParams.makeLink(p.matches[0], needLabel);
		if (!htmlMode) {
			return link.label;
		}
		else {
			string label = needLabel ? encode(link.href) : parseAll!true(p.children);
			return `<a`
				~ (link.cssClass ? ` class="`~link.cssClass~`"` : "")
				~ ` href="`~encode(link.href)~`">`
				~ label
			~ `</a>`;
		}
	}
}


private string processNode__Bold(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<strong>` ~ parseAll!true(p.children) ~ `</strong>`
		: parseAll!false(p.children);
}


private string processNode__Italic(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<em>` ~ parseAll!true(p.children) ~ `</em>`
		: parseAll!false(p.children);
}


private string processNode__Del(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<del>` ~ parseAll!true(p.children) ~ `</del>`
		: parseAll!false(p.children);
}


private string processNode__Code(bool htmlMode)(ParseTree p) {
	return htmlMode
		? `<code>` ~ parseAll!true(p.children) ~ `</code>`
		: parseAll!false(p.children);
}


private string processNode__Block(bool htmlMode)(ParseTree p) {
	if (!htmlMode) {
		return parseAll!false(p.children);
	}
	else {
		string result;
		inlineCutsToOpen = [];
		blockCutsToOpen = [];
		inlineCutsToClose = [];
		blockCutsToClose = [];
		
		// Open blockquote, if needed
		result ~= replicate("<blockquote>\n\n", numOfBlockquotesOpenedByLine.get(p.begin, size_t.init));
		
		// Find out which cuts should be opened or closed at the block's margins.
		foreach (cut; allCuts) {
			if (cut.blocks[0].begin == p.begin && cut.firstBlockIsFull)
				// Current block is the first block inside a block cut.
				blockCutsToOpen ~= cut;
				
			if (cut.blocks[$-1].end == p.end && cut.lastBlockIsFull)
				// Current block is the last block inside a block cut.
				blockCutsToClose ~= cut;
				
			if (cut.blocks.length >= 2) {
				// Cut that contain two or more blocks sometimes can be divided into two or three parts.
				// The first/last part may be a <span>, while the rest of cut is <div>.
				// This is when the first/last part does not cover the whole block.
				
				if (cut.blocks[0].begin == p.begin && !cut.blocks[0].fromTheBeginning)
					// This is the first block, and it is <span>.
					inlineCutsToClose ~= cut;
					
				if (cut.blocks[1].begin == p.begin && !cut.blocks[0].fromTheBeginning && cut.blocks[1].toTheEnd)
					// This is the second block in the cut, but the first one inside its <div> part.
					blockCutsToOpen ~= cut;
					
				if (cut.blocks[$-2].end == p.end && cut.blocks[$-2].fromTheBeginning && !cut.blocks[$-1].toTheEnd)
					// This is the second last block in the cut, but the last one inside its <div> part.
					blockCutsToClose ~= cut;
					
				if (cut.blocks[$-1].end == p.end && !cut.blocks[$-1].toTheEnd)
					// This is the last block, and it is <span>.
					inlineCutsToOpen ~= cut;
			}
		}
		
		// Check if the block begins with one or more cut openings.
		foreach (cut; blockCutsToOpen)
			if (cut.blocks[0].begin == p.begin)
				result ~= "<div class=\"cut\">"~encode(cut.label)~"</div>\n<div class=\"undercut\">\n\n";
			else
				result ~= "<div class=\"undercut\">\n\n";
		
		// Then, render the block itself.
		result ~= parseAll!htmlMode(p.children);
		
		// Finally, check if the block ends with one or more cut endings.
		foreach (cut; blockCutsToClose)
			result ~= "</div>\n\n";
			
		// Close blockquote, if needed
		result ~= (p.begin == lastBlockBegin)
			? replicate("</blockquote>\n\n", quotationLevels[p.begin])
			: replicate("</blockquote>\n\n", numOfBlockquotesClosedByLine.get(p.begin, 0));
		
		// Ready
		isCurrentBlockFirst = false;
		return result;
	}
}


private string processNode__BeginCut(bool htmlMode)(ParseTree p) {
	// We only render openings of inline cuts here.
	// Endings of inline cuts are rendered in "Liara.Block".
	CutInfo cut = cutsByBeginIndex[p.begin];
	if (htmlMode && !cut.firstBlockIsFull && !inlineCutsToOpen.canFind(cut))
		return "<span class=\"cut\">"~encode(cut.label)~"</span><span class=\"undercut\">";
	else
		return "";
}


private string processNode__EndCut(bool htmlMode)(ParseTree p) {
	// We only render endings of inline cuts here.
	// Endings of block cuts are rendered in "Liara.Block".
	if (htmlMode && p.end in cutsByEndIndex) {
		CutInfo cut = cutsByEndIndex[p.end];
		if (!blockCutsToClose.canFind(cut))
			return "</span>";
	}
	return "";
}


private string processNode__QuotationMark(bool htmlMode)(ParseTree p) {
	return htmlMode ? "" : p.input[p.begin..p.end];
}


private string processNode__Ruler(bool htmlMode)(ParseTree p) {
	return htmlMode ? "<hr/>\n\n" : p.input[p.begin..p.end]~"\n\n";
}


private string processNode__NewLine(bool htmlMode)(ParseTree p) {
	return htmlMode ? "<br/>\n" : "\n";
}


private string processNode__Heading(bool htmlMode)(ParseTree p) {
	if (!htmlMode) {
		return p.matches[$-1]~"\n\n";
	}
	else {
		ulong level = 7 - p.matches[0].length;
		string tag = "h" ~ level.to!string;
		
		if (p.matches.length > 2)
			return `<`~tag~`><a name="`~encode(p.matches[1])~`"></a> `~encode(p.matches[2])~`</`~tag~">\n\n";
		else
			return `<`~tag~`>`~encode(p.matches[1])~"</"~tag~">\n\n";
	}
}


// Block image ("!image.png" or "!!image.png") is rendered as <p><img/></p>.
private string processNode__BlockImage(bool htmlMode)(ParseTree p) {
	if (!htmlMode) {
		return "";
	}
	else {
		string attributes;             /// The attributes for <img>
		string[] pClasses = ["image"]; /// List of classes to be used for <p> around the <img>
		string link;                   /// Will be set to the image's link target
		
		// Use custom function to process the image URL
		string src = parserParams.processImageUrl(p.matches[1]);
		
		// By default, set "alt" attribute to the image name
		string alt = src.split("/")[$-1];
		
		// Now process optional arguments, one by one
		for (auto i=1; i<p.children.length; i++) {
			ParseTree c = p.children[i];
			final switch (c.name.replace(ctRegex!`^Liara\.`, ""))
			{
				case S!(Liara.ImgAlt):
					alt = c.matches[0];
					break;
				
				case S!(Liara.ImgSize):
					attributes ~= " width=\""~c.matches[0]~"\" height=\""~c.matches[1]~"\"";
					break;
				
				case S!(Liara.ImgLink):
					link = c.matches[0];
					break;
				
				case S!(Liara.ImgCenter): pClasses ~= "center"; break;
				case S!(Liara.ImgLeft):   pClasses ~= "left";   break;
				case S!(Liara.ImgRight):  pClasses ~= "right";  break;
			}
		}
		
		// Now render <img>...
		string result = "<img alt=\""~encode(alt)~"\" src=\""~encode(src)~"\""~attributes~"/>";
		
		// ...wrap it in <a> if necessary...
		if (link)
			result = "<a href=\""~encode(link)~"\">"~result~"</a>";
		
		// ...wrap it in <p class="image"> (optionally with some additional classes) and return.
		return "<p class=\""~uniq(pClasses).join(" ")~"\">"~result~"</p>\n\n";
	}
}


private string processNode__CustomBlock(bool htmlMode)(ParseTree p) {
	if (!htmlMode)
		return "["~p.matches[0]~"]\n\n";
	else
		try {
			string pluginName = p.matches[0];
			string pluginInput = p.matches.length>1 ? p.matches[1] : "";
			bool addLast = (parserParams.addClassLast && p.begin == lastBlockBegin);
			return parserParams.makeBlock(pluginName, pluginInput, addLast);
		}
		catch (UnsupportedPluginException e) {
			// Return the raw code as is
			return p.input[p.begin..p.end];
		}
}


private string processNode__Pre(bool htmlMode)(ParseTree p) {
	immutable string language = p.matches.length>1 ? p.matches[0] : null;
	immutable string source = p.matches[$-1];
	
	if (!htmlMode)
		return source~"\n\n";
	else if (language)
		return "<pre data-language=\""~language~"\">\n"~encode(source)~"\n</pre>\n\n";
	else
		return "<pre>\n"~encode(source)~"\n</pre>\n\n";
}


private string parseAll(bool htmlMode)(ParseTree[] nodes) {
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