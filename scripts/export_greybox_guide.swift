#!/usr/bin/env swift

import AppKit
import Foundation

let canvasWidth = 2_048
let canvasHeight = 1_536
let tableWidth = CGFloat(canvasWidth) * 0.70
let consoleWidth = CGFloat(canvasWidth) - tableWidth

let outputURL: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("NovaStationPinball/Resources/Art/greybox-table-guide.png")
}()

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: canvasWidth,
    pixelsHigh: canvasHeight,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Unable to allocate the greybox bitmap")
}

func fill(_ rect: NSRect, color: NSColor) {
    color.setFill()
    NSBezierPath(rect: rect).fill()
}

func stroke(_ rect: NSRect, color: NSColor, width: CGFloat, dash: [CGFloat] = []) {
    color.setStroke()
    let path = NSBezierPath(rect: rect)
    path.lineWidth = width
    if !dash.isEmpty {
        path.setLineDash(dash, count: dash.count, phase: 0)
    }
    path.stroke()
}

func circle(center: NSPoint, radius: CGFloat, fillColor: NSColor, strokeColor: NSColor) {
    let rect = NSRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    fillColor.setFill()
    strokeColor.setStroke()
    let path = NSBezierPath(ovalIn: rect)
    path.lineWidth = 8
    path.fill()
    path.stroke()
}

func label(_ text: String, at point: NSPoint, size: CGFloat, color: NSColor = .white) {
    text.draw(
        at: point,
        withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .bold),
            .foregroundColor: color
        ]
    )
}

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    fatalError("Unable to create the greybox graphics context")
}
NSGraphicsContext.current = context

fill(NSRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight), color: .black)
fill(NSRect(x: 0, y: 0, width: tableWidth, height: CGFloat(canvasHeight)), color: NSColor(white: 0.13, alpha: 1))
fill(NSRect(x: tableWidth, y: 0, width: consoleWidth, height: CGFloat(canvasHeight)), color: NSColor(red: 0.03, green: 0.07, blue: 0.05, alpha: 1))
stroke(NSRect(x: 10, y: 10, width: canvasWidth - 20, height: canvasHeight - 20), color: .white, width: 10)
stroke(NSRect(x: 55, y: 70, width: tableWidth - 110, height: CGFloat(canvasHeight) - 160), color: .systemYellow, width: 5, dash: [20, 14])
stroke(NSRect(x: tableWidth + 35, y: 45, width: consoleWidth - 70, height: CGFloat(canvasHeight) - 90), color: .systemGreen, width: 7)

label("GREYBOX GUIDE — NOT FINAL ART", at: NSPoint(x: 78, y: 1_445), size: 38, color: .systemYellow)
label("TABLE 70%", at: NSPoint(x: 78, y: 1_385), size: 28)
label("MECHANICAL SAFE ZONE", at: NSPoint(x: 80, y: 96), size: 24, color: .systemYellow)
label("CRT CONSOLE 30%", at: NSPoint(x: tableWidth + 58, y: 1_445), size: 28, color: .systemGreen)
label("4:3 MASTER 2048 × 1536", at: NSPoint(x: tableWidth + 58, y: 1_385), size: 19)

circle(center: NSPoint(x: 510, y: 1_065), radius: 82, fillColor: .darkGray, strokeColor: .white)
circle(center: NSPoint(x: 865, y: 1_065), radius: 82, fillColor: .darkGray, strokeColor: .white)
circle(center: NSPoint(x: 687, y: 800), radius: 82, fillColor: .darkGray, strokeColor: .white)
label("BUMPER", at: NSPoint(x: 455, y: 1_055), size: 20)
label("BUMPER", at: NSPoint(x: 810, y: 1_055), size: 20)
label("BUMPER", at: NSPoint(x: 632, y: 790), size: 20)

for index in 0 ..< 4 {
    let x = 360 + CGFloat(index) * 205
    fill(NSRect(x: x, y: 1_260, width: 82, height: 120), color: .gray)
    stroke(NSRect(x: x, y: 1_260, width: 82, height: 120), color: .white, width: 5)
}
label("TARGET BANK", at: NSPoint(x: 600, y: 1_305), size: 22)

NSColor.white.setStroke()
let leftFlipper = NSBezierPath()
leftFlipper.move(to: NSPoint(x: 390, y: 315))
leftFlipper.line(to: NSPoint(x: 625, y: 350))
leftFlipper.lineWidth = 42
leftFlipper.lineCapStyle = .round
leftFlipper.stroke()
let rightFlipper = NSBezierPath()
rightFlipper.move(to: NSPoint(x: 1_010, y: 315))
rightFlipper.line(to: NSPoint(x: 775, y: 350))
rightFlipper.lineWidth = 42
rightFlipper.lineCapStyle = .round
rightFlipper.stroke()
label("FLIPPERS", at: NSPoint(x: 610, y: 245), size: 24)

fill(NSRect(x: tableWidth - 115, y: 120, width: 48, height: 205), color: .gray)
stroke(NSRect(x: tableWidth - 115, y: 120, width: 48, height: 205), color: .white, width: 5)
label("PLUNGER", at: NSPoint(x: tableWidth - 215, y: 75), size: 20)

label("SCORE", at: NSPoint(x: tableWidth + 75, y: 1_220), size: 26, color: .systemGreen)
label("000000000", at: NSPoint(x: tableWidth + 75, y: 1_130), size: 46, color: .systemGreen)
label("BALLS   3", at: NSPoint(x: tableWidth + 75, y: 980), size: 28, color: .systemGreen)
label("RANK    CADET", at: NSPoint(x: tableWidth + 75, y: 910), size: 28, color: .systemGreen)
label("MISSION READY", at: NSPoint(x: tableWidth + 75, y: 540), size: 28, color: .systemGreen)
label("HUD SAFE AREA", at: NSPoint(x: tableWidth + 75, y: 110), size: 24, color: .systemGreen)

NSGraphicsContext.restoreGraphicsState()

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to encode the greybox PNG")
}
try pngData.write(to: outputURL, options: .atomic)
print("Exported deterministic greybox guide: \(outputURL.path) (\(canvasWidth)x\(canvasHeight))")
