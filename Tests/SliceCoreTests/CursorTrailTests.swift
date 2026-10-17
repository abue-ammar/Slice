//
//  CursorTrailTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreImage
@testable import SliceCore
import XCTest

final class CursorTrailTests: XCTestCase {
    let renderer = FrameRenderer()
    let output = CGSize(width: 1200, height: 800)
    let screenPoints = CGSize(width: 1512, height: 982)

    /// What the trail kernel replaces: each pose's sprite placed on its own, crossfaded, then averaged.
    private func chained(_ current: CursorSprite, _ previous: CursorSprite?, fade: Double, poses: [(CursorPose, CGRect)],
                         size: CGFloat, raster: CGFloat) -> CIImage {
        func placed(_ s: CursorSprite, _ pose: CursorPose, _ content: CGRect) -> CIImage {
            let hot = CGPoint(x: content.minX + pose.position.x * content.width,
                              y: output.height - (content.minY + pose.position.y * content.height))
            let f = content.width / screenPoints.width * size / raster
            return s.image.transformed(by: CGAffineTransform(translationX: -s.hotspot.x, y: -s.hotspot.y)
                .concatenating(CGAffineTransform(scaleX: f, y: f))
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(pose.angle)))
                .concatenating(CGAffineTransform(translationX: hot.x, y: hot.y)))
        }
        return renderer.average(poses.map { pose, content in
            let now = placed(current, pose, content)
            guard let previous else { return now }
            return renderer.scaleAlpha(now, by: fade).applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: renderer.scaleAlpha(placed(previous, pose, content), by: 1 - fade),
            ])
        })
    }

    /// Over a backdrop, as the pointer always is in a frame.
    private func pixels(_ image: CIImage) -> [UInt8] {
        let bounds = CGRect(origin: .zero, size: output)
        let backdrop = CIImage(color: CIColor(red: 0.4, green: 0.55, blue: 0.7)).cropped(to: bounds)
        var out = [UInt8](repeating: 0, count: Int(output.width * output.height) * 4)
        renderer.context.render(image.composited(over: backdrop), toBitmap: &out, rowBytes: Int(output.width) * 4, bounds: bounds,
                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return out
    }

    private func assertMatches(previous: CursorType?, fade: Double, count: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNotNil(FrameRenderer.cursorTrailKernel, "kernel compiles", file: file, line: line)
        let raster: CGFloat = 1.5
        let current = try XCTUnwrap(CursorSprite.render(style: .native, type: .arrow, scale: raster))
        let other = try previous.map { try XCTUnwrap(CursorSprite.render(style: .native, type: $0, scale: raster)) }
        // A curved sweep under a zoom easing in, so the scale, angle and place all change along the trail.
        let poses: [(CursorPose, CGRect)] = (0 ..< count).map { i in
            let u = count > 1 ? Double(i) / Double(count - 1) : 0
            let pose = CursorPose(position: CGPoint(x: 0.3 + 0.35 * u, y: 0.4 + 0.15 * sin(u * 3)), angle: -0.3 * u)
            let k = 1 + 0.6 * u
            let content = CGRect(x: -200 * (k - 1), y: -120 * (k - 1), width: output.width * k, height: output.height * k)
            return (pose, content)
        }
        let kernel = try XCTUnwrap(renderer.trailLayer(current, other, fade: fade, poses: poses, screenPoints: screenPoints,
                                                       size: 1.4, raster: raster, output: output))
        let reference = chained(current, other, fade: fade, poses: poses, size: 1.4, raster: raster)
        let a = pixels(kernel), b = pixels(reference)
        let worst = zip(a, b).map { abs(Int($0) - Int($1)) }.max() ?? 0
        let drawn = stride(from: 0, to: b.count, by: 4).filter { b[$0] != b[0] || b[$0 + 2] != b[2] }.count
        XCTAssertGreaterThan(drawn, 100, "the reference draws a pointer", file: file, line: line)
        XCTAssertLessThanOrEqual(worst, 3, "kernel matches the chained sprites", file: file, line: line)
    }

    func testSinglePoseMatches() throws {
        try assertMatches(previous: nil, fade: 1, count: 1)
    }

    func testTrailMatches() throws {
        try assertMatches(previous: nil, fade: 1, count: 23)
        try assertMatches(previous: nil, fade: 1, count: FrameRenderer.maxTrail)
    }

    func testCrossfadeBetweenShapesMatches() throws {
        try assertMatches(previous: .pointingHand, fade: 0.35, count: 1)
        try assertMatches(previous: .pointingHand, fade: 0.6, count: 17)
    }
}
