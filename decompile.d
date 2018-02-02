module bldso;
import std.stdio;
import std.conv;
import std.array;
import core.exception;

enum opcodes {
	FILLER0,
	OP_ADVANCE_STR_NUL,
	OP_UINT_TO_STR,
	OP_UINT_TO_NONE,
	FILLER1,
	OP_ADD_OBJECT,
	FILLER2,
	OP_CALLFUNC_RESOLVE,
	OP_FLT_TO_UINT,
	OP_FLT_TO_STR,
	OP_STR_TO_NONE_2,
	OP_LOADVAR_UINT,
	OP_SAVEVAR_STR,
	OP_JMPIFNOT,
	OP_SAVEVAR_FLT,
	OP_LOADIMMED_UINT,
	OP_LOADIMMED_FLT,
	OP_LOADIMMED_IDENT,
	OP_TAG_TO_STR,
	OP_LOADIMMED_STR,
	OP_ADVANCE_STR_APPENDCHAR,
	OP_TERMINATE_REWIND_STR,
	OP_ADVANCE_STR,
	OP_CMPLE,
	OP_SETCURFIELD,
	OP_SETCURFIELD_ARRAY,
	OP_JMPIF_NP,
	OP_JMPIFF,
	OP_JMP,
	OP_BITOR,
	OP_SHL,
	OP_SHR,
	OP_STR_TO_NONE,
	OP_COMPARE_STR,
	OP_CMPEQ,
	OP_CMPGR,
	OP_CMPNE, 
	OP_OR,
	OP_STR_TO_UINT,
	OP_SETCUROBJECT,
	OP_PUSH_FRAME,
	OP_REWIND_STR,
	OP_LOADFIELD_UINT_2,
	OP_CALLFUNC,
	OP_LOADVAR_STR,
	OP_LOADVAR_FLT,
	OP_SAVEFIELD_FLT,
	OP_LOADFIELD_FLT,
	OP_MOD,
	OP_LOADFIELD_UINT,
	OP_JMPIFFNOT,
	OP_JMPIF,
	OP_SAVEVAR_UINT,
	OP_SUB,
	OP_MUL,
	OP_DIV,
	OP_NEG,
	FILLER3,
	OP_STR_TO_FLT,
	OP_END_OBJECT,
	OP_CMPLT,
	OP_BREAK,
	OP_SETCURVAR_CREATE,
	OP_SETCUROBJECT_NEW,
	OP_NOT,
	OP_NOTF,
	OP_SETCURVAR,
	OP_SETCURVAR_ARRAY,
	OP_ADD,
	OP_SETCURVAR_ARRAY_CREATE,
	OP_JMPIFNOT_NP,
	OP_AND,
	OP_RETURN,
	OP_XOR,
	OP_CMPGE,
	OP_LOADFIELD_STR,
	OP_SAVEFIELD_STR,
	OP_BITAND,
	OP_ONESCOMPLEMENT,
	OP_ADVANCE_STR_COMMA,
	OP_PUSH,
	OP_FLT_TO_NONE,
	OP_CREATE_OBJECT,
	OP_FUNC_DECL,
	DECOMPILER_ENDFUNC = 0x1111
}

enum CallTypes {
	FunctionCall, //A regular call. May have a namespace.
	ObjectCall, //Object and/or MethodCall
	ParentCall, //idk dude
	FunctionDecl //Something I just added in for shits and giggles tbh
}	

File curFile;

void decompile(char[] global_st, char[] function_st, double[] global_ft, double[] function_ft, int[] code, int[] lbptable, string dso_name = "", bool entered_function = false, int offset = 0, int tablevel = 0) {
	import std.algorithm, std.string;
	writeln("Code length: ", code.length);
	int i = 0;
	bool create_folders = false;
	int indentation_level = tablevel;
	bool enteredFunction = entered_function, enteredObjectCreation = false; //Needed if we enter into an object creation for some reason?
	string[] string_stack;
	string[] int_stack;
	string[] float_stack;
	string[] bin_stack;
	string[][] arguments;
	int[] lookback_stack = [0, 0, 0, 0];
	string current_object = "", current_field = "", current_variable = "";
	string string_op(char inchar) {
		switch(inchar) {
			case '\n':
				return "NL";
			case '\t':
				return "TAB";
			case ' ':
				return "@";

			default:
				return "";
		}
	}
	string constructPrettyFunction(string fnName, string fnNamespace, string[] argv, CallTypes callType = CallTypes.FunctionCall) {
		string retVal = "";
		if(fnNamespace != "") {
			retVal ~= fnNamespace ~ "::" ~ fnName;
		}
		else {
			retVal ~= fnName;
		}
		retVal ~= "(";
			if(argv.length == 1) {
				retVal ~= argv[0];
			}
			else {
				for(int i = 0; i < argv.length; i++) {
					retVal ~= argv[i];
					if(i != argv.length - 1)
					{
						retVal ~= ", ";
					}
				}
			}

		retVal ~= ")";
		return retVal;
	}

	string popOffStack(ref string[] instack) {
		string ret;
		ret = instack[instack.length - 1];
		instack = instack.remove(instack.length - 1);
		return ret;
	}
	string get_string(int offset, bool fuck = enteredFunction) {
		//writeln()
		char[] blehtable;
		if(!fuck) {
			blehtable = global_st[offset..global_st.length];		
		}
		else {
			blehtable = function_st[offset..function_st.length];
		}


		int endPartOfString = cast(int)countUntil(blehtable, "\x00");
		//writeln("End portion of string: ", endPartOfString);
		//writeln("Attempt to slice out the string: ", blehtable[0..endPartOfString]);
		char[] slicedString = blehtable[0..endPartOfString];
		return text(slicedString.ptr);
	}

	float get_float(int offset, bool fuck = enteredFunction) {
		float retval;
		if(!fuck) {
			retval = global_ft[offset];
		}
		else {
			retval = function_ft[offset];
		}
		return retval;
	}

	string addTabulation(string previous) {
		string retVal = "";
		for(int l = 0; l < indentation_level; l++) {
			retVal ~= "\t";
		}
		retVal ~= previous;
		return retVal;
	}

	if(dso_name != "") { //If this happens, then, we're probably doing a partial decompile.
		int fileExtension = cast(int)countUntil(dso_name, ".cs.dso");
		string file_name_with_fixed_ext = dso_name[0..fileExtension] ~ ".cs";
		//writeln(dso_name[0..fileExtension]);{
		curFile = File(file_name_with_fixed_ext, "w");
	}
	while(i < code.length) {
		opcodes opcode = cast(opcodes)code[i];
		i++;
		//Pop one off the front, then append it to the back.
		lookback_stack = lookback_stack.remove(0);
		lookback_stack.insertInPlace(3, opcode);
		writeln(to!string(opcode));
		try {
			switch(opcode) {
				case opcodes.OP_FUNC_DECL: {
					string fnName = get_string(code[i]);
					string fnNamespace = get_string(code[i + 1]);
					if(code[i + 1] == 0) {
						fnNamespace = "";
					}
					string fnPackage = get_string(code[i + 2]);
					int has_body, fnEndLoc, argc;
					has_body = code[i + 3];
					fnEndLoc = code[i + 4];
					argc = code[i + 5];
					string[] argv;
					int whatWasThere = code[fnEndLoc];
					//code.insertBefore(fnEndLoc, opcodes_meta.DECOMPILER_ENDFUNC);
					code.insertInPlace(fnEndLoc, opcodes.DECOMPILER_ENDFUNC);
					writeln("New function");
					//code[fnEndLoc] = opcodes_meta.DECOMPILER_ENDFUNC;
					writeln(lookback_stack);
					writeln("fnName: ", fnName, " fnNamespace: ", fnNamespace, " fnPackage: ", fnPackage, " has_body: ", has_body, " fnEndLoc: ", fnEndLoc, " argc ", argc);
					//writeln(global_st[code[i]]);
					//writeln(code[ip]);
					//writeln("Code end loc: ", fnEndLoc, " code size: ", code.length);
					//writeln("Thing at code end loc: ", code[fnEndLoc]);
					enteredFunction = true;
					if(code[fnEndLoc] == opcodes.DECOMPILER_ENDFUNC) {
						writeln("fnEndLoc inserted successfully");
					}
					if(code[fnEndLoc + 1] == whatWasThere) {
						writeln("OPCode directly after is saved..");
					}
					//writeln("Found a function declaration");
					for(int q = 0; q < argc; q++) {
						argv ~= get_string(code[i + 6 + q]);
					//	argv ~= text(function_st[code[i + 6 + q]]);
					}
					curFile.writeln("function " ~ constructPrettyFunction(fnName, fnNamespace, argv) ~ " {");
					indentation_level++;
					//writeln(constructPrettyFunction(fnName, fnNamespace, argv));
					//i += 6 + argc;
					decompile(global_st, function_st, global_ft, function_ft, code[i + 6 + argc..fnEndLoc - 2], lbptable, "", enteredFunction, i + 6 + argc, indentation_level);
					i = fnEndLoc - 1;
					writeln(argv);
					break;
				}

				case opcodes.DECOMPILER_ENDFUNC: { //our metadata that we inserted
					writeln("encountered endfunc at ", i - 1);
					code = code.remove(i - 1); //we encountered it, now delete it because offsets are fucky
					indentation_level--; //tabs or spaces??
					curFile.writeln(addTabulation("}"));
					writeln("code at pos: ", code[i - 1]);
					enteredFunction = false;
					i--;
					break;
				}

				case opcodes.OP_CALLFUNC_RESOLVE, opcodes.OP_CALLFUNC: {
					int call_type = code[i + 2];
					//writeln("Got call type");
					//writeln(code[i], " ", enteredFunction ? function_st.length : global_st.length);
					string fnName = get_string(code[i], false);
					//writeln("Got fnName");
					string fnNamespace = "";
					if(code[i + 1]) {
						fnNamespace = get_string(code[i + 1], false);
					}
					writeln(arguments);
					string[] argv = arguments[arguments.length - 1];
					arguments = arguments.remove(arguments.length - 1);
					//writeln(argv);
					string_stack ~= constructPrettyFunction(fnName, fnNamespace, argv, cast(CallTypes)call_type);
					i += 3;
					break;
				}

				case opcodes.OP_RETURN: {
					//writeln("return ", string_stack.length);
					//writeln(string_stack[string_stack.length]);
					string writeOut = addTabulation("");
					writeOut ~= "return";
					if(string_stack.length != 0) {
						string ret = popOffStack(string_stack);
						writeOut ~= " " ~ ret ~ ";";
					}
					else {
						writeOut ~= ";";
					}

					if(i != code.length && code[i] != opcodes.DECOMPILER_ENDFUNC) {
						curFile.writeln(writeOut);
					}
					break;
				}

				case opcodes.OP_PUSH_FRAME: {
					arguments ~= [[]];
					writeln(arguments);
					break;
				}

				case opcodes.OP_PUSH: {
					//if(lookback_stack[3] == opcodes.OP_LOADVAR_FLT || lookback_stack[3] == opcodes.OP_LOADVAR_STR || lookback_stack[3] == opcodes.OP_LOADVAR_FLT) {
					arguments[arguments.length - 1] ~= [popOffStack(string_stack)];
					break;
				}

				case opcodes.OP_CREATE_OBJECT: {
					string parent = get_string(code[i], false);
					int isDatablock = code[i + 1], failJump = code[i + 2];
					string constr = "new";
					break;
				}

				case opcodes.OP_ADD_OBJECT: {
					i++;
					break;
				}

				case opcodes.OP_SETCUROBJECT: {
					current_object = popOffStack(string_stack);
					break;
				}

				case opcodes.OP_SETCUROBJECT_NEW: {
					current_object = "";
					break;
				}

				case opcodes.OP_SETCURVAR, opcodes.OP_SETCURVAR_CREATE: {
					current_variable = get_string(code[i], false);
					i++;
					break;
				}

				case opcodes.OP_SETCURVAR_ARRAY, opcodes.OP_SETCURVAR_ARRAY_CREATE: {
					current_variable = popOffStack(string_stack);
					break;
				}

				case opcodes.OP_SETCURFIELD: {
					current_field = get_string(code[i], false);
					break;
				}

				case opcodes.OP_SETCURFIELD_ARRAY: {
					auto hnng = popOffStack(string_stack);
					current_field ~= "[" ~ hnng ~ "]";
					break;
				}

				case opcodes.OP_LOADVAR_STR, opcodes.OP_LOADVAR_FLT, opcodes.OP_LOADVAR_UINT: {
					if(opcode == opcodes.OP_LOADVAR_STR) {
						string_stack ~= current_variable;
					}
					else if(opcode == opcodes.OP_LOADVAR_FLT) {
						float_stack ~= current_variable;
					}
					else if(opcode == opcodes.OP_LOADVAR_UINT) {
						int_stack ~= current_variable;
					}
					break;
				}

				case opcodes.OP_LOADIMMED_STR, opcodes.OP_TAG_TO_STR: {
					auto str = "\"" ~ get_string(code[i]) ~ "\"";
					i++;
					if(opcode == opcodes.OP_TAG_TO_STR) {
						str = str.replace("'", "");
					}
					string_stack ~= str;
					break;
				}

				case opcodes.OP_LOADIMMED_IDENT, opcodes.OP_LOADIMMED_FLT, opcodes.OP_LOADIMMED_UINT: {
					if(opcode == opcodes.OP_LOADIMMED_IDENT) {
						string_stack ~= get_string(code[i], false);
					}
					else if(opcode == opcodes.OP_LOADIMMED_FLT) {
						float_stack ~= to!string(get_float(code[i]));
					}
					else if(opcode == opcodes.OP_LOADIMMED_UINT) {
						int_stack ~= to!string(code[i]);
					}
					i++;
					break;
				}

				case opcodes.OP_STR_TO_NONE, opcodes.OP_FLT_TO_NONE, opcodes.OP_UINT_TO_NONE: {
					//writeln(string_stack);
					//Return value is ignored, so we can immediately write it out.
					//writeln(string_stack, " ", string_stack.length);
					string theFunc;
					if(opcode == opcodes.OP_STR_TO_NONE) {
						theFunc = addTabulation(popOffStack(string_stack));
					}
					else if(opcode == opcodes.OP_FLT_TO_NONE) {
						popOffStack(float_stack);
						break;
						//theFunc = addTabulation(popOffStack(float_stack));
					}
					else if(opcode == opcodes.OP_UINT_TO_NONE) {
						popOffStack(int_stack);
						break;
						//theFunc = addTabulation(popOffStack(int_stack));
					}
					//writeln(theFunc);
					if(theFunc[theFunc.length - 1] != ";"[0]) {
						theFunc ~= ";";
					}
					curFile.writeln(theFunc);
					break;
				}

				case opcodes.OP_STR_TO_FLT, opcodes.OP_STR_TO_UINT: {
					if(opcode == opcodes.OP_STR_TO_FLT) {
						float_stack ~= popOffStack(string_stack);
					}
					else if(opcode == opcodes.OP_STR_TO_UINT) {
						int_stack ~= popOffStack(int_stack);
					}
					break;
				}

				case opcodes.OP_FLT_TO_STR, opcodes.OP_FLT_TO_UINT: {
					if(opcode == opcodes.OP_FLT_TO_STR) {
						string_stack ~= popOffStack(float_stack);
					}
					else if(opcode == opcodes.OP_FLT_TO_UINT) {
						int_stack ~= popOffStack(float_stack);
					}
					break;
				}

				case opcodes.OP_UINT_TO_STR: {
					string_stack ~= popOffStack(int_stack);
					break;
				}

				case opcodes.OP_SAVEVAR_UINT, opcodes.OP_SAVEVAR_FLT, opcodes.OP_SAVEVAR_STR: {
					string part2;
					if(opcode == opcodes.OP_SAVEVAR_UINT) {
						part2 = int_stack[int_stack.length - 1];
					}
					else if(opcode == opcodes.OP_SAVEVAR_FLT) {
						part2 = float_stack[float_stack.length - 1];
					}
					else if(opcode == opcodes.OP_SAVEVAR_STR) {
						part2 = string_stack[string_stack.length - 1];
					}
					if(part2[part2.length - 1] != ";"[0]) { //lmfao
						part2 ~= ";";
					}
					curFile.writeln(addTabulation(current_variable ~ " = " ~ part2));
					break;
				}

				case opcodes.OP_JMPIFNOT, opcodes.OP_JMPIF, opcodes.OP_JMPIF_NP: {
					i++;
					break;
				}

				case opcodes.OP_SAVEFIELD_STR, opcodes.OP_SAVEFIELD_FLT: {
					string thing;
					if(opcode == opcodes.OP_SAVEFIELD_STR) {
						writeln("Breathing you in when I want you out.");
						writeln(string_stack.length);
						thing = string_stack[string_stack.length - 1];
					}
					else {
						thing = float_stack[float_stack.length - 1];
					}
					if(current_object != "") {
						//writeln("Test");
						if(current_object[0] == '$' || current_object[0] == '%') {
							curFile.writeln(addTabulation(current_object ~ "." ~ current_field ~ " = " ~ thing ~ ";"));
						}
						else {
							curFile.writeln(addTabulation("\"" ~ current_object ~ "\"" ~ "." ~ current_field ~ " = " ~ thing ~ ";"));
						}
					}
					else {
						//Then we're in an object creation.
						//writeln("Tired of home");
						if(enteredObjectCreation) {
							int_stack ~= popOffStack(int_stack) ~ current_field ~ " = " ~ thing ~ ";";
						}
						else {
							curFile.writeln(addTabulation(current_field ~ " = " ~ thing ~ ";"));
						}
					}
					break;
				}

				case opcodes.OP_COMPARE_STR: {
					string after = popOffStack(string_stack); //???
					int_stack ~= popOffStack(string_stack) ~ " $= " ~ after;
					break;
				}

				case opcodes.OP_REWIND_STR: {
					if(code[i] == opcodes.OP_SETCURVAR_ARRAY || code[i] == opcodes.OP_SETCURVAR_ARRAY_CREATE) {
						string after = popOffStack(string_stack);
						string_stack ~= popOffStack(string_stack) ~ "[" ~ after ~ "]";
					}
					else {
						string part2 = popOffStack(string_stack), part1 = popOffStack(string_stack);
						if(string_op(part1[part1.length - 1]) != "") {
							string_stack ~= part1[0..part1.length - 2] ~ " " ~ string_op(part1[part1.length - 1]) ~ " " ~ part2;
						}
						else if(part1[part1.length - 1] == ',') {
							string_stack ~= part1 ~ part2;
						}
						else {
							string_stack ~= part1 ~ " @ " ~ part2;
						}
					}
					//writeln(string_stack);
					break;

				}

				case opcodes.OP_ADVANCE_STR_COMMA: {
					string_stack ~= popOffStack(string_stack) ~ ",";
					break;
				}

				case opcodes.OP_ADVANCE_STR_APPENDCHAR: {
					string_stack ~= popOffStack(string_stack) ~ cast(char)code[i];
					i++;
					break;
				}

				default: {
					break;
				//writeln("Unhandled");
				}
			}
		}
		catch(RangeError) {
			writeln("Encountered a RangeError.. at ip: ", i - 1);
			writeln("Opcode here is: ", code[i - 1]);
			//writeln(code[i + 2]);
			curFile.close();
			writeln(function_st.length);
			return;
		}
	}

	if(dso_name != "") {
		writeln("you won't feel a thing");
		writeln(arguments);
		//writeln(lookback_stack);
		//writeln(string_stack);
		curFile.close();
	}
	//writeln("todo");
}