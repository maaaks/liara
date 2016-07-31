module liara.nodes;

import liara;
public import liara.nodes.custom;
public import liara.nodes.cuts;
public import liara.nodes.formatting;
public import liara.nodes.images;
public import liara.nodes.links;
public import liara.nodes.text;


/**
	Process a node of the parse tree.
	
	Initially it is called from parseLiara() for the entire tree and recursively calls itself for its nodes.
 */
string processNode(bool htmlMode)(ParseTree p) {
	switch (p.name) {
		case "Liara.AutoUrl":       return processNode_AutoUrl!htmlMode(p);
		case "Liara.BasicChar":     return processNode_BasicChar!htmlMode(p);
		case "Liara.BeginCut":      return processNode_BeginCut!htmlMode(p);
		case "Liara.Block":         return processNode_Block!htmlMode(p);
		case "Liara.BlockImage":    return processNode_BlockImage!htmlMode(p);
		case "Liara.Bold":          return processNode_Bold!htmlMode(p);
		case "Liara.Code":          return processNode_Code!htmlMode(p);
		case "Liara.CustomBlock":   return processNode_CustomBlock!htmlMode(p);
		case "Liara.Del":           return processNode_Del!htmlMode(p);
		case "Liara.EndCut":        return processNode_EndCut!htmlMode(p);
		case "Liara.Heading":       return processNode_Heading!htmlMode(p);
		case "Liara.Italic":        return processNode_Italic!htmlMode(p);
		case "Liara.Line":          return processNode_Line!htmlMode(p);
		case "Liara.Link":          return processNode_Link!htmlMode(p);
		case "Liara.NewLine":       return processNode_NewLine!htmlMode(p);
		case "Liara.NoFormat":      return processNode_NoFormat!htmlMode(p);
		case "Liara.Paragraph":     return processNode_Paragraph!htmlMode(p);
		case "Liara.PlainChar":     return processNode_PlainChar!htmlMode(p);
		case "Liara.Pre":           return processNode_Pre!htmlMode(p);
		case "Liara.QuotationMark": return processNode_QuotationMark!htmlMode(p);
		case "Liara.Ruler":         return processNode_Ruler!htmlMode(p);
		case "Liara.Text":          return processNode_Text!htmlMode(p);
		default: return parseAll!htmlMode(p.children);
	}
}