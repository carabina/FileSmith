//
//  File.swift
//  FileSmith
//
//  Created by Kåre Morstøl on 03/12/2016.
//

import Foundation

public class File: TextOutputStreamable {
	public let path: FilePath
	public var encoding: String.Encoding = .utf8
	public let type: FileType
	let filehandle: FileHandle

	fileprivate init(path: FilePath, filehandle: FileHandle, type: FileType? = nil) {
		self.filehandle = filehandle
		self.path = path
		self.type = type ?? FileType(fileDescriptor: filehandle.fileDescriptor)
	}

	fileprivate static func errorForFile(at stringpath: String, writing: Bool) throws {
		guard let type = FileType(stringpath) else {
			throw FileSystemError.notFound(path: FilePath(stringpath))
		}
		if case .directory = type {
			throw FileSystemError.isDirectory(path: DirectoryPath(stringpath))
		}
		throw FileSystemError.invalidAccess(path: FilePath(stringpath), writing: writing)
	}

	public convenience init(open path: FilePath) throws {
		guard let filehandle = FileHandle(forReadingAtPath: path.absoluteString) else {
			try File.errorForFile(at: path.absoluteString, writing: false)
			fatalError("Should have thrown error when opening \(path.absoluteString)")
		}
		self.init(path: path, filehandle: filehandle)
	}

	public convenience init(open stringpath: String) throws {
		try self.init(open: FilePath(stringpath))
	}


	/// Writes the text in this file to the given TextOutputStream.
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

	/// Splits stream lazily into lines.
	public func lines () -> LazyMapSequence<PartialSourceLazySplitSequence<String.CharacterView>, String> {
		return PartialSourceLazySplitSequence({self.readSome()?.characters}, separator: "\n").map { String($0) }
	}

	public func close() {
		filehandle.closeFile()
	}
}

extension FilePath {
	public func open() throws -> File {
		return try File(open: self)
	}
}



public class EditableFile: File {

	public convenience init(open path: FilePath) throws {
		try path.verifyIsInSandbox()
		guard let filehandle = FileHandle(forUpdatingAtPath: path.absoluteString) else {
			try File.errorForFile(at: path.absoluteString, writing: true)
			fatalError("Should have thrown error when opening \(path.absoluteString)")
		}
		self.init(path: path, filehandle: filehandle)
	}

	fileprivate static func createFile(path: FilePath, ifExists: AlreadyExistsOptions) throws {
		let stringpath = path.absoluteString

		if let type = FileType(stringpath) {
			guard type != .directory else {
				throw FileSystemError.isDirectory(path: DirectoryPath(stringpath))
			}
			switch ifExists {
			case .throwError:	throw FileSystemError.alreadyExists(path: path)
			case .open: return
			case .replace: break
			}
		} else {
			try path.verifyIsInSandbox()
			try path.parent().create(ifExists: .open)
		}
		try path.verifyIsInSandbox()
		guard FileManager().createFile(atPath: stringpath, contents: Data(), attributes: nil) else {
			throw FileSystemError.couldNotCreate(path: FilePath(stringpath))
		}
	}

	public convenience init(create path: FilePath, ifExists: AlreadyExistsOptions) throws {
		try EditableFile.createFile(path: path, ifExists: ifExists)
		try self.init(open: path)
	}

	public convenience init(create stringpath: String, ifExists: AlreadyExistsOptions) throws {
		try self.init(create: FilePath(stringpath), ifExists: ifExists)
	}
}

extension EditableFile: TextOutputStream {
	/// Appends the string to the file.
	/// Nothing is overwritten, just added to the end of the file.
	public func write(_ string: String) {
		if type == .regularFile { _ = filehandle.seekToEndOfFile() }
		filehandle.write(string, encoding: encoding)
	}

	/// Replaces the entire contents of the file with the string.
	/// - warning: The current contents of the file will be lost.
	/// - warning: Will crash if this is not a regular file.
	public func overwrite(_ string: String) {
		filehandle.seek(toFileOffset: 0)
		filehandle.write(string, encoding: encoding)
		filehandle.truncateFile(atOffset: filehandle.offsetInFile)
		filehandle.synchronizeFile()
	}

	public func delete() throws {
		try FileManager().removeItem(atPath: path.absoluteString)
	}
}

extension FilePath {
	public func edit() throws -> EditableFile {
		return try EditableFile(open: self)
	}

	@discardableResult
	public func create(ifExists: AlreadyExistsOptions) throws -> EditableFile {
		return try EditableFile(create: self, ifExists: ifExists)
	}
}
