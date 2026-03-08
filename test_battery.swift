import Foundation
import IOKit.ps

let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
print("Success")
