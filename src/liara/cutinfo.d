module liara.cutinfo;

import pegged.grammar;

/**
	Information about cut block, collected with PEG's Semantic Actions.
 */
class CutInfo
{
	immutable string id;    /// Unique name to be used in IDs for HTML elements.
	immutable string label; /// Label to be shown when the cut is collapsed.
	CuttedBlock[] blocks;   /// Information about which blocks are cutted fully and which are partially.
	
	this(in string id, in string label) {
		this.id = id;
		this.label = label;
	}
	
	CuttedBlock addBlock(in ParseTree p) {
		// Try to find block
		foreach (block; blocks)
			if (block.begin == p.begin)
				return block;
			
		// Or, add the block as a new one
		blocks ~= new CuttedBlock(p.begin, p.end);
		return blocks[$-1];
	}
	
	CuttedBlock findBlock(in ParseTree p) {
		foreach (block; blocks)
			if (block.begin == p.begin)
				return block;
		return null;
	}
	
	bool firstBlockIsFull() const {
		return blocks[0].fromTheBeginning && blocks[0].toTheEnd;
	}
	
	bool lastBlockIsFull() const {
		return blocks[$-1].fromTheBeginning && blocks[$-1].toTheEnd;
	}
}


class CuttedBlock
{
	size_t begin;          /// Index of the block's first character.
	size_t end;            /// Index of the block's last character.
	bool fromTheBeginning; /// Whether the cut starts where the block starts.
	bool toTheEnd;         /// Whether the cut ends where the block ends.
	
	private this(in size_t begin, in size_t end) {
		this.begin = begin;
		this.end = end;
	}
	
	override string toString() const {
		return "["~begin.to!string~":"~end.to!string~"], "~fromTheBeginning.to!string~", "~toTheEnd.to!string;
	}
}