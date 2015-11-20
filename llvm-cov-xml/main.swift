//
//  main.swift
//  llvm-cov-xml
//
//  Created by Yury Popov on 28 окт..
//  Copyright © 2015 DJ PhoeniX. All rights reserved.
//

import Foundation

struct RegEx {
	static let Scheme = (try? NSRegularExpression(pattern: "(\\n|^)    Schemes:\\n((        [^\\n]+\\n)+)(\\n|$)", options: []))!
	static let FileBegin = (try? NSRegularExpression(pattern: "^(\\/.*)\\:$", options: []))!
	static let UncoveredLine = (try? NSRegularExpression(pattern: "^\\s+\\|\\s+\\d+\\|", options: []))!
	static let LineCoverage = (try? NSRegularExpression(pattern: "^\\s+\\d+(\\.\\d+[Ek])?\\|\\s+\\d+\\|", options: []))!
	static let BranchCoverage = (try? NSRegularExpression(pattern: "^(\\s*\\^\\d+(\\.\\d+k)?)+$", options: []))!
	static let BranchCoverageData = (try? NSRegularExpression(pattern: "\\^\\d+(\\.\\d+k)?", options: []))!
}
struct Config {
	var workDir: String
	var output: String
	var verbose: Bool
	var exclude: [String]
	
	var buildvars: [String:String]
	var scheme: String
	var coverage: String
	var executable: String
}
typealias FileName = String
struct BranchCoverage {
	var hits: Int
}
struct LineCoverage {
	var number: Int
	var hits: Int
	var branches: [BranchCoverage]
}
typealias FileCoverage = Array<LineCoverage>

func resolvePath(path: String, from: String) -> String {
	var path = (path as NSString).stringByStandardizingPath
	path = (path as NSString).stringByExpandingTildeInPath
	if !path.hasPrefix("/") {
		path = (from as NSString).stringByAppendingPathComponent(path)
	}
	path = (path as NSString).stringByStandardizingPath
	return path
}

func relativePath(path: String, to: String) -> String {
	var pc1 = (path as NSString).pathComponents
	var pc2 = (to as NSString).pathComponents
	while pc1.first != nil && pc1.first == pc2.first {
		pc1.removeFirst()
		pc2.removeFirst()
	}
	while pc2.count > 0 {
		pc1.insert("..", atIndex: 0)
		pc2.removeFirst()
	}
	return pc1.joinWithSeparator("/")
}

let fileManager = NSFileManager.defaultManager()
let nullout = NSFileHandle.fileHandleWithNullDevice()
let stdout = NSFileHandle.fileHandleWithStandardOutput()
let stderr = NSFileHandle.fileHandleWithStandardError()
var config = Config(
	workDir: fileManager.currentDirectoryPath,
	output: (fileManager.currentDirectoryPath as NSString).stringByAppendingPathComponent("coverage.xml"),
	verbose: false,
	exclude: [],
	
	buildvars: [:],
	scheme: "",
	coverage: "",
	executable: ""
)
var coverage = [FileName:FileCoverage]()
func run(proc: String, args: [String]) -> NSData {
	let task = NSTask(), out = NSPipe(), handle = out.fileHandleForReading, mdata = NSMutableData()
	handle.readabilityHandler = {(handle) -> () in
		mdata.appendData(handle.availableData)
	}
	task.launchPath = proc
	task.arguments = args
	task.currentDirectoryPath = config.workDir
	task.standardError = nullout
	task.standardOutput = out
	task.launch()
	task.waitUntilExit()
	mdata.appendData(handle.readDataToEndOfFile())
	return NSData(data: mdata)
}
func eprint(s: String) {
	if let data = (s + "\n").dataUsingEncoding(NSUTF8StringEncoding) {
		stderr.writeData(data)
	}
}
func vprint(s: String) {
	if config.verbose { eprint(s) }
}
func print_usage() {
	let prog = NSProcessInfo.processInfo().processName
	let strings: [String] = [
		"Usage: \(prog) [-v | --verbose] [-o OUTFILE | --output OUTFILE] [-e MASK | --exclude MASK] [-r ROOT | --root ROOT]",
		"       \(prog) [-u | --usage]",
		"       -u --usage    Prints available arguments (this text)",
		"       -e --exclude  Exclude files/directories with mask",
		"                     (format: path prefixes/full paths, comma-separated)",
		"       -v --verbose  Verbose logging",
		"       -o --output   Output file path",
		"                     (default: coverage.xml)",
		"       -r --root     Source root directory",
		"                     (default: current directory)"
	]
	if let data = ((strings as NSArray).componentsJoinedByString("\n")+"\n").dataUsingEncoding(NSUTF8StringEncoding) {
		stderr.writeData(data)
	}
}
func process_args() {
	var args = NSProcessInfo.processInfo().arguments.suffixFrom(1)
	if args.contains("-v") || args.contains("--verbose") {
		if let idx = args.indexOf("-v") { args.removeAtIndex(idx) }
		if let idx = args.indexOf("--verbose") { args.removeAtIndex(idx) }
		config.verbose = true
	}
	if args.contains("-u") || args.contains("--usage") {
		if let idx = args.indexOf("-u") { args.removeAtIndex(idx) }
		if let idx = args.indexOf("--usage") { args.removeAtIndex(idx) }
		print_usage()
		exit(EXIT_SUCCESS)
	}
	if args.contains("-r") || args.contains("--root") {
		let idx = (args.indexOf("-r") ?? args.indexOf("--root"))!
		if args.count < idx+1 {
			eprint("\(args[idx]) option requires an argument")
			print_usage()
			exit(EXIT_FAILURE)
		}
		let root = resolvePath(args[idx+1], from: fileManager.currentDirectoryPath)
		config.workDir = root
		config.output = (root as NSString).stringByAppendingPathComponent("coverage.xml")
		args.removeAtIndex(idx+1)
		args.removeAtIndex(idx)
	}
	if args.contains("-e") || args.contains("--exclude") {
		let idx = (args.indexOf("-e") ?? args.indexOf("--exclude"))!
		if args.count < idx+1 {
			eprint("\(args[idx]) option requires an argument")
			print_usage()
			exit(EXIT_FAILURE)
		}
		config.exclude = args[idx+1].componentsSeparatedByString(",").map({ (str) -> String in
			return relativePath(resolvePath(str, from: config.workDir), to: config.workDir)
		})
		args.removeAtIndex(idx+1)
		args.removeAtIndex(idx)
	}
	if args.contains("-o") || args.contains("--output") {
		let idx = (args.indexOf("-o") ?? args.indexOf("--output"))!
		if args.count < idx+1 {
			eprint("\(args[idx]) option requires an argument")
			print_usage()
			exit(EXIT_FAILURE)
		}
		var out = args[idx+1]
		if out != "-" {
			out = resolvePath(args[idx+1], from: fileManager.currentDirectoryPath)
			var isDir: ObjCBool = false
			if fileManager.fileExistsAtPath(out, isDirectory: &isDir) && isDir {
				out = (out as NSString).stringByAppendingPathComponent("coverage.xml")
			}
		}
		config.output = out
		args.removeAtIndex(idx+1)
		args.removeAtIndex(idx)
	}
	var isDir: ObjCBool = false
	if !fileManager.fileExistsAtPath(config.workDir, isDirectory: &isDir) || !isDir {
		eprint("Directory '\(config.workDir)' not exists.")
		exit(EXIT_FAILURE)
	}
	if args.count > 0 {
		eprint("Unknown argument: \(args[0])")
		print_usage()
		exit(EXIT_FAILURE)
	}
}
func find_scheme() {
	if let list = String(data: run("/usr/bin/xcodebuild", args: ["-list"]), encoding: NSUTF8StringEncoding) {
		let schemes = RegEx.Scheme.matchesInString(list, options: [], range: NSRange(location: 0, length: list.characters.count))
		if schemes.count > 0 {
			if let scheme = (list as NSString).substringWithRange(schemes[0].range).componentsSeparatedByString("\n").filter({ (str) -> Bool in
				return str != ""
			}).suffixFrom(1).map({ (str) -> String in
				return str.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			}).first {
				config.scheme = scheme
				return
			}
		}
	}
	eprint("Cannot find default scheme")
	exit(EXIT_FAILURE)
}
func buildvars() {
	if let vars_str = String(data: run(
		"/usr/bin/xcodebuild",
		args: [
			"-scheme",config.scheme,
			"test",
			"-enableCodeCoverage","YES",
			"-showBuildSettings"
		]), encoding: NSUTF8StringEncoding) {
			var vars = [String:String]()
			vars_str.componentsSeparatedByString("\n\n").first!.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet()).componentsSeparatedByString("\n").suffixFrom(1).map({ (str) -> String in
				return str.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
			}).forEach({ (str) -> () in
				let comps = str.componentsSeparatedByString(" = ")
				let name = comps.first!
				let value = (Array(comps.suffixFrom(1)) as NSArray).componentsJoinedByString(" = ")
				vars[name] = value
			})
			config.buildvars = vars
	}
}
func find_cov_paths() {
	if let tempDir = config.buildvars["TEMP_ROOT"], exePath = config.buildvars["EXECUTABLE_PATH"] {
		let covDir = (tempDir as NSString).stringByAppendingPathComponent("CodeCoverage/\(config.scheme)")
		let covFile = (covDir as NSString).stringByAppendingPathComponent("Coverage.profdata")
		let covProducts = (covDir as NSString).stringByAppendingPathComponent("Products")
		var isDir: ObjCBool = false
		if !fileManager.fileExistsAtPath(covFile, isDirectory: &isDir) || isDir {
			eprint("Cannot find coverage data, run tests first.")
			exit(EXIT_FAILURE)
		}
		if !fileManager.fileExistsAtPath(covProducts, isDirectory: &isDir) || !isDir {
			eprint("Cannot find coverage data, run tests first.")
			exit(EXIT_FAILURE)
		}
		config.coverage = covFile
		let products = (try? fileManager.contentsOfDirectoryAtPath(covProducts)) ?? []
		var latestDate: NSDate? = nil, latestExe: String? = nil
		for p in products {
			let root = (covProducts as NSString).stringByAppendingPathComponent(p)
			let exe = (root as NSString).stringByAppendingPathComponent(exePath)
			if let date = (try? fileManager.attributesOfItemAtPath(exe))?[NSFileModificationDate] as? NSDate {
				if (latestDate?.timeIntervalSince1970 ?? -NSTimeInterval.infinity) < date.timeIntervalSince1970 {
					latestDate = date; latestExe = exe
				}
			}
		}
		if let exe = latestExe {
			config.executable = exe
			return
		} else {
			eprint("Cannot find executable file")
			exit(EXIT_FAILURE)
		}
	}
}
func process_hits(s: String) -> Int? {
	if let i = Int(s) { return i }
	if s.hasSuffix("k") || s.hasSuffix("E"), let f = Double(s.substringToIndex(s.endIndex.advancedBy(-1))) {
		return Int(f*1000)
	}
	print(s)
	return nil
}
func checkExclude(path: String) -> Bool {
	if config.exclude.contains(path) { return true }
	for ex in config.exclude {
		if path.hasPrefix(ex) {
			return true
		}
	}
	return false
}
func process_covdata() {
	if let lines = String(data: run(
		"/usr/bin/xcrun",
		args: [
			"llvm-cov", "show",
			"-show-line-counts-or-regions",
			config.executable,
			"-instr-profile=\(config.coverage)"
		]
		), encoding: NSUTF8StringEncoding)?.componentsSeparatedByString("\n") {
			var file: String? = nil, line: FileCoverage.Index? = nil
			for l in lines {
				if RegEx.FileBegin.matchesInString(l, options: [], range: NSRange(location: 0, length: l.characters.count)).count > 0 {
					let fn = relativePath(l.substringToIndex(l.endIndex.advancedBy(-1)), to: config.workDir)
					if !fn.hasPrefix("../") {
						if !checkExclude(fn) {
							file = fn
							coverage[fn] = [LineCoverage]()
							vprint("Pricessing \(fn)")
						} else {
							file = nil
							vprint("Skipped \(fn)")
						}
					} else {
						file = nil
					}
					continue
				}
				if let _ = file where RegEx.UncoveredLine.matchesInString(l, options: [], range: NSRange(location: 0, length: l.characters.count)).count > 0 {
					line = nil
					continue
				}
				if let file = file where RegEx.LineCoverage.matchesInString(l, options: [], range: NSRange(location: 0, length: l.characters.count)).count > 0 {
					let comps = l.componentsSeparatedByString("|").prefix(2).map({ (str) -> String in
						return str.stringByTrimmingCharactersInSet(NSCharacterSet.whitespaceAndNewlineCharacterSet())
					})
					if let num = Int(comps[1]), hits = process_hits(comps[0]) {
						line = coverage[file]?.endIndex
						coverage[file]?.append(LineCoverage(number: num, hits: hits, branches: []))
					} else {
						eprint("Failed to process hit count at line: \(l)")
					}
					continue
				}
				if let file = file, line = line where RegEx.BranchCoverage.matchesInString(l, options: [], range: NSRange(location: 0, length: l.characters.count)).count > 0 {
					for b in RegEx.BranchCoverageData.matchesInString(l, options: [], range: NSRange(location: 0, length: l.characters.count)) {
						var r = b.range
						r.location++; r.length--
						let b = (l as NSString).substringWithRange(r)
						if let hits = process_hits(b) {
							coverage[file]?[line].branches.append(BranchCoverage(hits: hits))
						} else {
							eprint("Failed to process hit count at line: \(l)")
						}
					}
					continue
				}
			}
	}
}
func getBranchRate(files: [FileCoverage]) -> Double {
	var total: Int = 0, covered: Int = 0
	for file in files {
		for line in file {
			for branch in line.branches {
				total++
				if branch.hits > 0 { covered++ }
			}
		}
	}
	if total == 0 { return 1 }
	return Double(covered) / Double(total)
}
func getLineRate(files: [FileCoverage]) -> Double {
	var total: Int = 0, covered: Int = 0
	for file in files {
		for line in file {
			total++
			if line.hits > 0 { covered++ }
		}
	}
	if total == 0 { return 1 }
	return Double(covered) / Double(total)
}
func getBranchRate() -> Double {
	return getBranchRate(Array(coverage.values))
}
func getLineRate() -> Double {
	return getLineRate(Array(coverage.values))
}
func getPackages() -> [String:[FileName]] {
	var packages = [String:[FileName]]()
	for (file, _) in coverage {
		var comps = file.componentsSeparatedByString("/")
		comps.removeLast()
		let pack = comps.joinWithSeparator(".")
		if packages[pack] == nil { packages[pack] = [] }
		packages[pack]?.append(file)
	}
	return packages
}
func getBranchRateString(branches: [BranchCoverage]) -> String {
	var total: Int = 0, covered: Int = 0
	for branch in branches {
		total++
		if branch.hits > 0 { covered++ }
	}
	if total == 0 { return "100% (0/0)" }
	let int = Int(Double(covered) / Double(total) * 100)
	return "\(int)% (\(covered)/\(total))"
}
func gen_xml() {
	if config.output != "-" {
		let _ = try? fileManager.removeItemAtPath(config.output)
		fileManager.createFileAtPath(config.output, contents: nil, attributes: nil)
	}
	if let out = config.output == "-" ? stdout : NSFileHandle(forWritingAtPath: config.output) {
		let write = {(s: String) -> Void in
			if let data = s.dataUsingEncoding(NSUTF8StringEncoding) {
				out.writeData(data)
			}
		}
		write("<?xml version=\"1.0\" ?>\n")
		write("<!DOCTYPE coverage SYSTEM 'http://cobertura.sourceforge.net/xml/coverage-03.dtd'>\n")
		let srcRoot = (config.output == "-") ? "." : relativePath(config.workDir, to: (config.output as NSString).stringByDeletingLastPathComponent)
		let branchRate = getBranchRate(), lineRate = getLineRate(), date = NSDate()
		write(" <coverage branch-rate=\"\(branchRate)\" line-rate=\"\(lineRate)\" timestamp=\"\(Int(date.timeIntervalSince1970))\" version=\"llvm-cov-xml 1.0\">\n")
		write(" <sources><source>\(srcRoot)</source></sources>\n")
		write(" <packages>\n")
		for (pack,files) in getPackages() {
			let files = files.map({ (name) -> (FileName,FileCoverage) in
				return (name,coverage[name]!)
			})
			let branchRate = getBranchRate(files.map({ (elem) -> FileCoverage in return elem.1})), lineRate = getLineRate(files.map({ (elem) -> FileCoverage in return elem.1}))
			write("  <package branch-rate=\"\(branchRate)\" complexity=\"0.0\" line-rate=\"\(lineRate)\" name=\"\(pack)\">\n")
			write("   <classes>\n")
			for (filename,file) in files {
				let branchRate = getBranchRate([file]), lineRate = getLineRate([file])
				let name = (filename as NSString).lastPathComponent.componentsSeparatedByCharactersInSet(NSCharacterSet.alphanumericCharacterSet().invertedSet).joinWithSeparator("_")
				write("    <class branch-rate=\"\(branchRate)\" complexity=\"0.0\" filename=\"\(filename)\" line-rate=\"\(lineRate)\" name=\"\(name)\">\n")
				write("     <methods/>\n")
				write("     <lines>\n")
				for line in file {
					write("      <line number=\"\(line.number)\" hits=\"\(line.hits)\"")
					if line.branches.count == 0 {
						write(" branch=\"false\"/>\n")
						continue
					}
					let branchRate = getBranchRateString(line.branches)
					write(" branch=\"true\" condition-coverage=\"\(branchRate)\">\n")
					write("       <conditions>\n")
					write("        <condition coverage=\"\(branchRate.componentsSeparatedByString(" ")[0])\" number=\"0\" type=\"jump\"/>\n")
					write("       </conditions>\n")
					write("      </line>\n")
				}
				write("     </lines>\n")
				write("    </class>\n")
			}
			write("   </classes>\n")
			write("  </package>\n")
		}
		write(" </packages>\n")
		write("</coverage>\n")
		out.closeFile()
	} else {
		eprint("Cannot output to \(config.output)")
	}
}

process_args()
vprint("Working directory: \(config.workDir)")
if config.output == "-" {
	vprint("Output: stdout")
} else {
	vprint("Output file: \(config.output)")
}
find_scheme()
vprint("Scheme: \(config.scheme)")
buildvars()
find_cov_paths()
vprint("Coverage file: \(config.coverage)")
vprint("Executable file: \(config.executable)")
process_covdata()
gen_xml()
