import Foundation

let fm = FileManager.default

if !fm.fileExists(atPath: SCLIInfo.shared.SuccessorCLIPath) {
    printIfDebug("Didn't find \(SCLIInfo.shared.SuccessorCLIPath) directory..proceeding to try to create it..")
    do {
        try fm.createDirectory(atPath: SCLIInfo.shared.SuccessorCLIPath, withIntermediateDirectories: true, attributes: nil)
        printIfDebug("Successfully created directory. Continuing.")
    } catch {
        fatalError("Error encountered while creating directory \(SCLIInfo.shared.SuccessorCLIPath): \(error.localizedDescription)\nNote: Please create the directory yourself and run SuccessorCLI again. Exiting")
    }
}

// We first need to filter out the program name, which always happens to be the first argument with CommandLine.arguments
let CMDLineArgs = CommandLine.arguments.filter() { $0 != CommandLine.arguments[0] }

printIfDebug("Args used: \(CMDLineArgs)")

for args in CMDLineArgs {
    switch args {
    case "--help", "-h":
        SCLIInfo.shared.printHelp()
        exit(0)
    case "-v", "--version":
        print("SuccessorCLI Version \(SCLIInfo.shared.ver)")
        exit(0)
    case "-d", "--debug":
        printIfDebug("DEBUG Mode Triggered.")
    case _ where CommandLine.arguments.contains("--dmg-path") && CommandLine.arguments.contains("--ipsw-path"):
        fatalError("Can't use both --dmg-path AND --ipsw-path together..exiting..")
        
        // Support for manually specifying iPSW:
        // This will unzip the iPSW, get RootfsDMG from it, attach and mount that, then execute restore.
    case "--ipsw-path":
        guard let index = CMDLineArgs.firstIndex(of: "--ipsw-path"), CMDLineArgs.indices.contains(index + 1) else {
            print("User used --ipsw-path, however the program couldn't get the iPSW Path specified, are you sure you specified one?")
            exit(EXIT_FAILURE)
        }
        let iPSWSpecified = CMDLineArgs[index + 1]
        printIfDebug("User manually specified iPSW Path to \(iPSWSpecified)")
        guard fm.fileExists(atPath: iPSWSpecified) && NSString(string: iPSWSpecified).pathExtension == "ipsw" else {
            fatalError("ERROR: file \"\(iPSWSpecified)\" Either doesn't exist or isn't an iPSW")
        }
        iPSWManager.onboardiPSWPath = iPSWSpecified
        iPSWManager.shared.unzipiPSW(iPSWFilePath: iPSWSpecified, destinationPath: iPSWManager.extractedOnboardiPSWPath)
        
        // Support for manually specifying rootfsDMG:
    case "--dmg-path":
        guard let index = CMDLineArgs.firstIndex(of: "--dmg-path"), CMDLineArgs.indices.contains(index + 1) else {
            print("User used --dmg-path, however the program couldn't get DMG Path specified, are you sure you specified one?")
            exit(EXIT_FAILURE)
        }
        let dmgSpecified = CMDLineArgs[index + 1]
        printIfDebug("User manually specified DMG Path to \(dmgSpecified)")
        guard fm.fileExists(atPath: dmgSpecified) && NSString(string: dmgSpecified).pathExtension == "dmg" else {
            fatalError("File \"\(dmgSpecified)\" Either doesnt exist or isnt a DMG file.")
        }
        DMGManager.shared.rfsDMGToUseFullPath = dmgSpecified
        
        // Support for manually specifying rsync binary:
    case "--rsync-bin-path":
        guard let index = CMDLineArgs.firstIndex(of: "--rsync-bin-path"), CMDLineArgs.indices.contains(index + 1) else {
            fatalError("User used --rsync-bin-path, however the program couldn't get Rsync executable Path specified, are you sure you specified one?")
        }
        let rsyncBinSpecified = CMDLineArgs[index + 1]
        guard fm.fileExists(atPath: rsyncBinSpecified), fm.isExecutableFile(atPath: rsyncBinSpecified) else {
            fatalError("File \"\(rsyncBinSpecified)\" Can't be used because it either doesn't exist or is not an executable file.")
        }
        printIfDebug("User manually specified rsync executable path as \(rsyncBinSpecified)")
        deviceRestoreManager.rsyncBinPath = rsyncBinSpecified
    default:
        break
    }
}

// detecting for root
// root is needed to execute rsync with enough permissions to replace all files necessary
guard getuid() == 0 else {
    fatalError("ERROR: SuccessorCLI Must be run as root, eg `sudo \(CommandLine.arguments.joined(separator: " "))`")
}

printIfDebug("Online iPSW URL: \(onlineiPSWInfo.iPSWURL)\nOnline iPSW Filesize (unformatted): \(onlineiPSWInfo.iPSWFileSize)\nOnline iPSW Filesize (formatted): \(onlineiPSWInfo.iPSWFileSizeForamtted)")
if isNT2() {
    print("[WARNING] NewTerm 2 Detected, I advise you to SSH Instead, as the huge output by rsync may crash NewTerm 2 mid restore.")
}
print("Welcome to SuccessorCLI! Version \(SCLIInfo.shared.ver).")
switch fm.fileExists(atPath: DMGManager.shared.rfsDMGToUseFullPath) {
case true:
    print("Found rootfsDMG at \(DMGManager.shared.rfsDMGToUseFullPath), Would you like to use it?")
    print("[1] Yes")
    print("[2] No")
    if let choice = readLine() {
        switch choice {
        case "1", "Y", "y":
            print("Proceeding to use \(DMGManager.shared.rfsDMGToUseFullPath)")
        case "2", "N", "n":
            print("User specified not to use RootfsDMG at \(DMGManager.shared.rfsDMGToUseFullPath). Exiting.")
            exit(0)
        default:
            print("Unkown input \"\(choice)\". Exiting.")
            exit(EXIT_FAILURE)
        }
    }

        // If there's already a DMG in SuccessorCLI Path, inform the user and ask if they want to use it
case false where !DMGManager.DMGSinSCLIPathArray.isEmpty:
    print("Found Following DMGs in \(SCLIInfo.shared.SuccessorCLIPath), Which would you like to use?")
    for i in 0...(DMGManager.DMGSinSCLIPathArray.count - 1) {
        print("[\(i)] Use DMG \(DMGManager.DMGSinSCLIPathArray[i])")
    }
    print("[\(DMGManager.DMGSinSCLIPathArray.count)] let SuccessorCLI download an iPSW for me automatically then extract the RootfsDMG from said iPSW.")
    // Input needs to be Int
    if let choice = readLine(), let choiceInt = Int(choice) {
        if choiceInt == DMGManager.DMGSinSCLIPathArray.count {
            iPSWManager.downloadAndExtractiPSW(iPSWURL: onlineiPSWInfo.iPSWURL)
        } else {
            guard DMGManager.DMGSinSCLIPathArray.indices.contains(choiceInt) else {
                fatalError("Inproper Input.")
            }
            let dmgSpecified = "\(SCLIInfo.shared.SuccessorCLIPath)/\(DMGManager.DMGSinSCLIPathArray[choiceInt])"
            DMGManager.shared.rfsDMGToUseFullPath = dmgSpecified
        }
    }
    break
    
    // If the case below is triggered, its because theres no rfs.dmg or any type of DMG in /var/mobile/Library/SuccessorCLI, note that DMGManager.DMGSinSCLIPathArray doesn't search the extracted path, explanation to why is at DMGManager.DMGSinSCLIPathArray's declaration
case false:
    print("No RootfsDMG Detected, what'd you like to do?")
    if !iPSWManager.iPSWSInSCLIPathArray.isEmpty {
    for i in 0...(iPSWManager.iPSWSInSCLIPathArray.count - 1) {
        print("[\(i)] Extract and use iPSW \"\(iPSWManager.iPSWSInSCLIPathArray[i])\"")
        }
    }
    print("[\(iPSWManager.iPSWSInSCLIPathArray.count)] let SuccessorCLI download an iPSW for me automatically")
    guard let input = readLine(), let intInput = Int(input) else {
        fatalError("Inproper Input.")
    }
    if intInput == iPSWManager.iPSWSInSCLIPathArray.count {
        iPSWManager.downloadAndExtractiPSW(iPSWURL: onlineiPSWInfo.iPSWURL)
    } else {
        guard iPSWManager.iPSWSInSCLIPathArray.indices.contains(intInput) else {
            fatalError("Inproper Input.")
        }
        let iPSWSpecified = iPSWManager.iPSWSInSCLIPathArray[intInput]
        iPSWManager.onboardiPSWPath = "\(SCLIInfo.shared.SuccessorCLIPath)/\(iPSWSpecified)"
        iPSWManager.shared.unzipiPSW(iPSWFilePath: iPSWManager.onboardiPSWPath, destinationPath: iPSWManager.extractedOnboardiPSWPath)
    }
}

if MntManager.shared.isMountPointMounted() {
    print("\(SCLIInfo.shared.mountPoint) Already mounted, skipping right ahead to the restore.")
} else {
    var diskNameToMnt = ""
    printIfDebug("Proceeding to (try) to attach DMG \"\(DMGManager.shared.rfsDMGToUseFullPath)\"")
    DMGManager.attachDMG(dmgPath: DMGManager.shared.rfsDMGToUseFullPath) { bsdName, err in
        // If the "else" statement is executed here, then that means the program either encountered an error while attaching (see attachDMG function declariation) or it couldn't get the name of the attached disk
        guard err == nil, let bsdName = bsdName else {
            fatalError("Error encountered while attaching DMG \"\(DMGManager.shared.rfsDMGToUseFullPath)\": \(err as? String ?? "Unknown Error")")
        }
        printIfDebug("Successfully attached DMG \"\(DMGManager.shared.rfsDMGToUseFullPath)\"")
        printIfDebug("Got attached disk name at \(bsdName)")
        diskNameToMnt = "/dev/\(bsdName)s1s1"
    }

    MntManager.mountNative(devDiskName: diskNameToMnt, mountPointPath: SCLIInfo.shared.mountPoint) { mntStatus in
        guard mntStatus == 0 else {
            fatalError("Wasn't able to mount successfully..error: \(String(cString: strerror(errno))). Exiting..")
        }
        print("Mounted \(diskNameToMnt) to \(SCLIInfo.shared.mountPoint) Successfully. Continiung!")
    }
}

switch CMDLineArgs {
case _ where CMDLineArgs.contains("--no-restore"):
    print("Successfully attached and mounted RootfsDMG, exiting now because the user used --no-restore.")
    exit(0)
case _ where !CMDLineArgs.contains("--no-wait"):
    print("You have 15 seconds to cancel the restore before it starts, to cancel, Press CTRL+C.")
    for time in 0...15 {
        sleep(UInt32(time))
        print("Starting restore in \(15 - time) Seconds.")
    }
default:
    break
}

print("Proceeding to launch rsync..")

deviceRestoreManager.launchRsync()
print("Rsync done, now time to reset device.")
deviceRestoreManager.callMobileObliterator()
