# slang-gdscript v0.2.2
# https://github.com/rensoftworks/slang-gdscript

# MIT License
#
# Copyright (c) 2025 Ren Softworks
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

class_name Slang

class Token:
	enum Type {
		WORD,
		NUMBER,
		EQUALS,
		LEFT_BRACE,
		RIGHT_BRACE,
		LEFT_SQUARE_BRACKET,
		RIGHT_SQUARE_BRACKET,
		SEPARATOR,
		HASH,
		NEWLINE,
		STRING,
		AT,
	}

	static var patterns: Dictionary = {
		Type.STRING: "^\\\"(\\\\\\\"|[^\\\"])*\\\"",
		Type.NUMBER: "^-?\\d+(\\.?\\d+)?",
		Type.AT:"^@",
		Type.WORD: "^[^\",\\s#\\\\\\n\\r=\\{\\}\\[\\]]+",
		Type.NEWLINE: "^\\s*[\\n\\r]+",
		Type.SEPARATOR: "^[,\\s]+",
		Type.EQUALS: "^=",
		Type.LEFT_BRACE: "^\\{",
		Type.RIGHT_BRACE: "^\\}",
		Type.LEFT_SQUARE_BRACKET: "^\\[",
		Type.RIGHT_SQUARE_BRACKET: "^\\]",
		Type.HASH: "^#"
	}

	var content: String
	var type: Type
	var position: int

	func _init(content: String, type: Type, position: int) -> void:
		self.content = content
		self.type = type
		self.position = position

	func inspect() -> String:
		return "{%d: %s = '%s'}" % [position, Type.keys()[type], content.replace("\n", "\\n").replace("\r", "\\r")]

class Lexer:
	var input: String
	var position: int = 0
	var regex: Dictionary = {}

	func _init(input: String) -> void:
		self.input = input
		
		for type in Token.patterns.keys():
			regex[type] = RegEx.new()
			regex[type].compile(Token.patterns[type])
		
	func next_token():
		if position >= input.length():
			return null

		var current_match = null
		var buffer = ""

		while position <= input.length()-1:

			for type in Token.patterns.keys():
				buffer = input.substr(position)
				current_match = regex[type].search(buffer)

				if current_match != null:
					var token = Token.new(current_match.strings[0], type, position)
					position = position + current_match.get_end()
					return token
		
		printerr("[Slang] Unknown token at position %d: '%s'" % [position, buffer])
		return null

class Parser:
	var lexer: Lexer
	var current_token: Token
	var mode_stack: Array[Mode] = []

	enum Mode {
		KEY,
		COMMENT,
		EQUALS,
		VALUE,
		DECLARE_CONSTANT,
		RETRIEVE_CONSTANT
	}

	var expected_tokens: Dictionary = {
		# Starting parse mode. Look for a key.
		Mode.KEY: [
			Token.Type.WORD,
			Token.Type.NUMBER,
			Token.Type.STRING,
			Token.Type.RIGHT_BRACE,
			Token.Type.HASH,
			Token.Type.SEPARATOR,
			Token.Type.NEWLINE,
			Token.Type.AT
		],

		Mode.DECLARE_CONSTANT: [
			Token.Type.WORD,
			Token.Type.NUMBER,
			Token.Type.STRING
		],

		Mode.RETRIEVE_CONSTANT: [
			Token.Type.WORD,
			Token.Type.NUMBER,
			Token.Type.STRING
		],

		# Find an equals sign
		Mode.EQUALS: [
			Token.Type.EQUALS,
			Token.Type.HASH,
			Token.Type.SEPARATOR,
			Token.Type.NEWLINE
		],

		# Look for a value
		Mode.VALUE: [
			Token.Type.WORD,
			Token.Type.NUMBER,
			Token.Type.STRING,
			Token.Type.LEFT_SQUARE_BRACKET,
			Token.Type.RIGHT_SQUARE_BRACKET,
			Token.Type.LEFT_BRACE,
			Token.Type.HASH,
			Token.Type.SEPARATOR,
			Token.Type.NEWLINE,
			Token.Type.AT
		],

		# Comment mode
		Mode.COMMENT: [
			Token.Type.NEWLINE,
			Token.Type.HASH, 
			Token.Type.WORD,
			Token.Type.NUMBER,
			Token.Type.EQUALS,
			Token.Type.LEFT_BRACE,
			Token.Type.RIGHT_BRACE,
			Token.Type.LEFT_SQUARE_BRACKET,
			Token.Type.RIGHT_SQUARE_BRACKET,
			Token.Type.SEPARATOR,
			Token.Type.STRING,
			Token.Type.AT
		]
	}

	func _init(input: String) -> void:
		lexer = Lexer.new(input)
		current_token = lexer.next_token()

	func _is_token_expected(mode: Mode, token: Token) -> bool:
		if !expected_tokens[mode].has(token.type):
			printerr("[Slang] Unexpected token %s at char %d: '%s'" % [Token.Type.keys()[current_token.type], current_token.position, current_token.content])
			return false
		
		return true

	func parse(constants: Dictionary = {}, debug: bool = false) -> Dictionary:
		var result: Dictionary = {}
		var constant_stack: Array[String] = []
		var key_stack: Array[String] = []
		var terminate: bool = false

		mode_stack.push_back(Mode.KEY)

		while current_token != null && !terminate:
			var mode = mode_stack.back()

			if debug:
				print("[Slang] Mode: %s, Token: %s" % [Mode.keys()[mode], current_token.inspect()])

			if !_is_token_expected(mode, current_token):
				return {}

			match mode:
				Mode.KEY:
					match current_token.type:
						Token.Type.HASH:
							_parse_comment(debug)

						Token.Type.AT:
							mode_stack.push_back(Mode.DECLARE_CONSTANT)

						Token.Type.WORD, Token.Type.NUMBER:
							key_stack.push_back(current_token.content)
							mode_stack.push_back(Mode.EQUALS)

						Token.Type.STRING:
							key_stack.push_back(current_token.content.trim_prefix("\"").trim_suffix("\""))
							mode_stack.push_back(Mode.EQUALS)

						Token.Type.RIGHT_BRACE:
							terminate = true

				Mode.DECLARE_CONSTANT:
					match current_token.type:
						Token.Type.WORD, Token.Type.NUMBER:
							constant_stack.push_back(current_token.content)
							mode_stack.pop_back()
							mode_stack.push_back(Mode.EQUALS)

						Token.Type.STRING:
							constant_stack.push_back(current_token.content.trim_prefix("\"").trim_suffix("\""))
							mode_stack.pop_back()
							mode_stack.push_back(Mode.EQUALS)

				Mode.RETRIEVE_CONSTANT:
					match current_token.type:
						Token.Type.WORD, Token.Type.NUMBER:
							if constant_stack.size() > 0:
								constants[constant_stack.pop_back()] = constants[current_token.content]
							else:
								result[key_stack.pop_back()] = constants[current_token.content]

							mode_stack.pop_back()
						Token.Type.STRING:
							if constant_stack.size() > 0:
								constants[constant_stack.pop_back()] = constants[current_token.content.trim_prefix("\"").trim_suffix("\"")]
							else:
								result[key_stack.pop_back()] = constants[current_token.content.trim_prefix("\"").trim_suffix("\"")]

							mode_stack.pop_back()

				Mode.EQUALS:
					match current_token.type:
						Token.Type.HASH:
							_parse_comment(debug)

						Token.Type.EQUALS:
							mode_stack.pop_back()
							mode_stack.push_back(Mode.VALUE)

				Mode.VALUE:
					match current_token.type:
						Token.Type.HASH:
							_parse_comment(debug)

						Token.Type.AT:
							mode_stack.pop_back()
							mode_stack.push_back(Mode.RETRIEVE_CONSTANT)

						Token.Type.WORD, Token.Type.NUMBER, Token.Type.STRING:
							if constant_stack.size() > 0:
								constants[constant_stack.pop_back()] = _parse_value()
							else:
								result[key_stack.pop_back()] = _parse_value()
							
							mode_stack.pop_back()

						Token.Type.LEFT_SQUARE_BRACKET:
							current_token = lexer.next_token()

							if constant_stack.size() > 0:
								constants[constant_stack.pop_back()] = _parse_array(constants, debug)
							else:
								result[key_stack.pop_back()] = _parse_array(constants, debug)

							mode_stack.pop_back()

						Token.Type.LEFT_BRACE:
							current_token = lexer.next_token()

							if constant_stack.size() > 0:
								constants[constant_stack.pop_back()] = parse(constants, debug)
							else:
								result[key_stack.pop_back()] = parse(constants, debug)

							mode_stack.pop_back()

				_:
					printerr("[Slang] Invalid parse mode for token %s at char %d: %s" % [Token.Type.keys()[current_token.type], current_token.position, current_token.content])
					return {}

			if !terminate:
				current_token = lexer.next_token()

		if debug:
			var mode_stack_message: String = "[Slang] Finished parsing with the following mode stack: ["
			for i in range(mode_stack.size()):
				mode_stack_message += Mode.keys()[mode_stack[i]]

				if i < mode_stack.size()-1:
					mode_stack_message += ", "
			mode_stack_message += "]"
			print(mode_stack_message)
			print("[Slang] Output: %s" % result)

		if terminate:
			mode_stack.pop_back()

		return result

	func _parse_value() -> Variant:
		match current_token.type:
			Token.Type.WORD:
				match current_token.content:
					"null":
						return null
					"true":
						return true
					"false":
						return false
					_:
						return current_token.content

			Token.Type.NUMBER:
				return float(current_token.content)

			Token.Type.STRING:
				return current_token.content.trim_prefix("\"").trim_suffix("\"").replace("\\", "")

			_:
				return null

	func _parse_array(constants: Dictionary = {}, debug: bool = false) -> Array:
		if debug:
			print("[Slang] Start parsing array")

		var buffer: Array = []
		var terminate: bool = false

		while current_token != null && !terminate:
			var mode = mode_stack.back()

			if debug:
				print("[Slang] Mode: %s, Token: %s" % [Mode.keys()[mode], current_token.inspect()])

			if !_is_token_expected(mode, current_token):
				return []

			match current_token.type:
				Token.Type.HASH:
					_parse_comment(debug)

				Token.Type.WORD, Token.Type.NUMBER, Token.Type.STRING:
					buffer.push_back(_parse_value())

				Token.Type.LEFT_SQUARE_BRACKET:
					current_token = lexer.next_token()
					buffer.push_back(_parse_array(constants, debug))

				Token.Type.LEFT_BRACE:
					current_token = lexer.next_token()
					buffer.push_back(parse(constants, debug))

				Token.Type.RIGHT_SQUARE_BRACKET:
					terminate = true

			if !terminate:
				current_token = lexer.next_token()

		if debug:
			print("[Slang] End parsing array")

		return buffer

	func _parse_comment(debug: bool):
		if debug:
			print("[Slang] Start parsing comment")

		var terminate: bool = false

		mode_stack.push_back(Mode.COMMENT)

		while current_token != null && !terminate:
			var mode = mode_stack.back()

			if debug:
				print("[Slang] Mode: %s, Token: %s" % [Mode.keys()[mode], current_token.inspect()])

			if !_is_token_expected(mode, current_token):
				return []

			match current_token.type:
				Token.Type.NEWLINE:
					terminate = true
					mode_stack.pop_back()

			if !terminate:
				current_token = lexer.next_token()

		if debug:
			print("[Slang] End parsing comment")

static func parse(string: String, debug: bool = false) -> Dictionary:
	return Parser.new(string).parse({}, debug)

static func stringify(dict: Dictionary, inline: bool = false) -> String:
	var string: String = ""

	for i in dict.keys().size():
		var key = dict.keys()[i]
		var value = dict[key]

		if typeof(key) == Variant.Type.TYPE_STRING:
			if key.contains(" "):
				key = "\"%s\"" % key

		string += "%s = " % key
		string += "%s" % [_stringify_value(value)]

		if inline:
			if i < dict.keys().size()-1:
				string += ", "
		else:
			string += "\n"

	return string

static func _stringify_value(value: Variant) -> String:
	var string = ""

	match typeof(value):
		TYPE_DICTIONARY:
			string += "{%s}" % stringify(value, true)

		TYPE_ARRAY:
			string += "["

			for i in value.size():
				string += "%s" % _stringify_value(value[i])

				if i < value.size()-1:
					string += ", "

			string += "]"

		TYPE_STRING:
			string += "\"%s\"" % value.replace("\"", "\\\"")

		TYPE_NIL:
			string += "null"

		_:
			string += "%s" % value

	return string
