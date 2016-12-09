//
//  File.swift
//  SwiftyPath
//
//  Created by Kåre Morstøl on 03/12/2016.
//
//

import Foundation

public class File {
	public let path: FilePath
	let filehandle: FileHandle
	public var encoding: String.Encoding = .utf8

	fileprivate init(path: FilePath, filehandle: FileHandle) {
		self.filehandle = filehandle
		self.path = path
	}

	fileprivate static func errorForFile(at stringpath: String, writing: Bool) throws {
		var isdirectory: ObjCBool = true
		guard Files.fileExists(atPath: stringpath, isDirectory: &isdirectory) else {
			throw FileSystemError.notFound(path: stringpath, base: nil)
		}
		guard !isdirectory.boolValue else {
			throw FileSystemError.isDirectory(path: stringpath)
		}
		throw FileSystemError.invalidAccess(path: stringpath, writing: writing)
	}

	public convenience init(open path: FilePath) throws {
		guard let filehandle = FileHandle(forReadingAtPath: path.absolute.string) else {
			try File.errorForFile(at: path.absolute.string, writing: false)
			fatalError("Should have thrown error when opening \(path.absolute.string)")
		}
		self.init(path: path, filehandle: filehandle)
	}

	public convenience init(open stringpath: String) throws {
		try self.init(open: FilePath(stringpath))
	}

	fileprivate static func createFile(path: FilePath, ifExists: AlreadyExistsOptions) throws {
		let stringpath = path.absolute.string

		var isdirectory: ObjCBool = true
		if Files.fileExists(atPath: stringpath, isDirectory: &isdirectory) {
			guard !isdirectory.boolValue else {
				throw FileSystemError.isDirectory(path: stringpath)
			}
			switch ifExists {
			case .throwError:	throw FileSystemError.alreadyExists(path: stringpath)
			case .open: return
			case .replace: break
			}
		} else {
			try path.parent().create(ifExists: .open)
		}
		try path.verifyIsInSandbox()
		guard Files.createFile(atPath: stringpath, contents: Data(), attributes: nil) else {
			throw FileSystemError.couldNotCreate(path: stringpath)
		}
	}

	public convenience init(create path: FilePath, ifExists: AlreadyExistsOptions) throws {
		try File.createFile(path: path, ifExists: ifExists)
		try self.init(open: path)
	}

	public convenience init(create stringpath: String, ifExists: AlreadyExistsOptions) throws {
		try self.init(create: FilePath(stringpath), ifExists: ifExists)
	}
}


extension File: TextOutputStreamable {
	/// Writes the text in this file to the given output stream.
	public func write<Target : TextOutputStream>(to target: inout Target) {
		while let text = filehandle.readSome(encoding: encoding) {
			target.write(text)
		}
	}

	public func read() -> String {
		return filehandle.read(encoding: encoding)
	}

	public func readSome() -> String? {
		return filehandle.readSome(encoding: encoding)
	}
}

extension FilePath {
	public func open() throws -> File {
		return try File(open: self)
	}
}



public class EditableFile: File {

	public init(edit path: FilePath) throws {
		try path.verifyIsInSandbox()
		guard let filehandle = FileHandle(forWritingAtPath: path.absolute.string) else {
			try File.errorForFile(at: path.absolute.string, writing: true)
			fatalError("Should have thrown error when opening \(path.absolute.string)")
		}
		super.init(path: path, filehandle: filehandle)
		filehandle.seekToEndOfFile()
	}

	public convenience init(edit stringpath: String) throws {
		try self.init(edit: FilePath(stringpath))
	}

	public convenience init(create path: FilePath, ifExists: AlreadyExistsOptions) throws {
		try File.createFile(path: path, ifExists: ifExists)
		try self.init(edit: path)
	}

	public convenience init(create stringpath: String, ifExists: AlreadyExistsOptions) throws {
		try self.init(create: FilePath(stringpath), ifExists: ifExists)
	}
}

extension EditableFile: TextOutputStream {
	/// Appends the given string to the stream.
	public func write(_ string: String) {
		filehandle.write(string, encoding: encoding)
	}
}

extension FilePath {
	public func edit() throws -> EditableFile {
		return try EditableFile(edit: self)
	}

	@discardableResult
	public func create(ifExists: AlreadyExistsOptions) throws -> EditableFile {
		return try EditableFile(create: self, ifExists: ifExists)
	}
}
