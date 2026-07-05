import Foundation
import Carbon.HIToolbox

func characterFromKeyCode(_ keyCode: Int) -> String? {
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    guard let dataPtr = layoutDataPtr else { return nil }
    
    let layoutData = unsafeBitCast(dataPtr, to: CFData.self)
    let keyLayoutPtr = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
    
    var deadKeyState: UInt32 = 0
    let maxLength = 4
    var chars = [UniChar](repeating: 0, count: maxLength)
    var actualLength = 0
    
    let status = UCKeyTranslate(
        keyLayoutPtr,
        UInt16(keyCode),
        UInt16(kUCKeyActionDown),
        0,
        UInt32(LMGetKbdType()),
        UInt32(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        maxLength,
        &actualLength,
        &chars
    )
    
    if status == noErr && actualLength > 0 {
        return String(utf16CodeUnits: chars, count: actualLength).uppercased()
    }
    return nil
}

print("Code 0:", characterFromKeyCode(0) ?? "nil")
print("Code 12:", characterFromKeyCode(12) ?? "nil")
