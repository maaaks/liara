module liara.runtime;

import liara.nodes.cuts;


/// Temporary variables used during parsing a document.
struct LiaraRuntime
{
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
}


package LiaraRuntime rt;