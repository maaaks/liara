module liara.nodes.text;

import liara;
import liara.nodes.cuts;
import std.array;
import std.string;
import std.xml;


package string processNode_Text(bool htmlMode)(ParseTree p) {
	isCurrentBlockFirst = true;
	return parseAll!htmlMode(p.children);
}


package string processNode_Paragraph(bool htmlMode)(ParseTree p) {
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


package string processNode_Line(bool htmlMode)(ParseTree p) {
	return parseAll!htmlMode(p.children).strip();
}


package string processNode_PlainChar(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


package string processNode_BasicChar(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


package string processNode_NoFormat(bool htmlMode)(ParseTree p) {
	return htmlMode ? encode(p.matches[0]) : p.matches[0];
}


package string processNode_Block(bool htmlMode)(ParseTree p) {
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