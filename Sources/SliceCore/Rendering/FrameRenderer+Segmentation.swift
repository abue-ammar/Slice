//
//  FrameRenderer+Segmentation.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

extension FrameRenderer {
    func takeSegmentationRequest(accurate: Bool) -> VNGeneratePersonSegmentationRequest {
        let level: VNGeneratePersonSegmentationRequest.QualityLevel = accurate ? .accurate : .balanced
        if let r = segmentationLock.withLock({ segmentation[level]?.popLast() }) { return r }
        let r = VNGeneratePersonSegmentationRequest()
        r.qualityLevel = level
        r.outputPixelFormat = kCVPixelFormatType_OneComponent8
        if let ane = (try? r.supportedComputeStageDevices)?[.main]?.first(where: {
            if case .neuralEngine = $0 { true } else { false }
        }) {
            r.setComputeDevice(ane, for: .main)
        }
        return r
    }

    func returnSegmentationRequest(_ r: VNGeneratePersonSegmentationRequest) {
        segmentationLock.withLock { segmentation[r.qualityLevel, default: []].append(r) }
    }

    func segment(_ image: CIImage, pixelBuffer: CVPixelBuffer?, accurate: Bool) -> CIImage? {
        let request = takeSegmentationRequest(accurate: accurate)
        defer { returnSegmentationRequest(request) }
        let handler = pixelBuffer.map { VNImageRequestHandler(cvPixelBuffer: $0) } ?? VNImageRequestHandler(ciImage: image)
        guard (try? handler.perform([request])) != nil, let buffer = request.results?.first?.pixelBuffer else { return nil }
        return CIImage(cvPixelBuffer: buffer)
    }

    func personMask(_ image: CIImage, pixelBuffer: CVPixelBuffer?, accurate: Bool) -> CIImage? {
        guard let pixelBuffer, let fingerprint = Self.fingerprint(pixelBuffer) else {
            return segment(image, pixelBuffer: pixelBuffer, accurate: accurate)
        }
        let key = MaskKey(fingerprint: fingerprint, accurate: accurate)
        let (entry, isNew): (MaskEntry, Bool) = segmentationLock.withLock {
            if let found = masks.last(where: { $0.key == key }) { return (found.entry, false) }
            let entry = MaskEntry()
            entry.lock.lock()
            masks.append((key, entry))
            if masks.count > 8 { masks.removeFirst() }
            return (entry, true)
        }
        if isNew {
            defer { entry.lock.unlock() }
            entry.mask = segment(image, pixelBuffer: pixelBuffer, accurate: accurate)
            return entry.mask
        }
        return entry.lock.withLock { entry.mask }
    }

    static func fingerprint(_ buffer: CVPixelBuffer) -> Int? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        guard let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        else { return nil }
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer)
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        let rowBytes = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let used = min(rowBytes, width * max(rowBytes / max(width, 1), 1))
        guard used >= 4, height > 0 else { return nil }
        var hasher = Hasher()
        hasher.combine(width)
        hasher.combine(height)
        for y in stride(from: 0, to: height, by: 8) {
            let row = base + y * rowBytes
            for x in stride(from: 0, to: used - 3, by: 28) {
                hasher.combine(row.loadUnaligned(fromByteOffset: x, as: UInt32.self))
            }
        }
        return hasher.finalize()
    }

    func blurBackground(_ image: CIImage, pixelBuffer: CVPixelBuffer?, strength: Double, accurate: Bool) -> CIImage {
        let extent = image.extent
        let raw = personMask(image, pixelBuffer: pixelBuffer, accurate: accurate)
        guard let raw else { return image }
        let up = CIFilter.lanczosScaleTransform()
        up.inputImage = raw
        up.scale = Float(extent.height / raw.extent.height)
        up.aspectRatio = Float((extent.width / raw.extent.width) / (extent.height / raw.extent.height))
        let mask = up.outputImage!.cropped(to: extent).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 2.5, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 2.5, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 2.5, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: -1.2, y: -1.2, z: -1.2, w: 0),
        ]).applyingFilter("CIColorClamp")

        let sigma = strength * extent.height * 0.03
        let grown = mask.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: extent.height * 0.02])
            .cropped(to: extent)
        let weighted = image.clampedToExtent().applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: grown.clampedToExtent().applyingFilter("CIColorInvert").applyingFilter("CIMaskToAlpha"),
        ])
        let blurredWeighted = weighted.applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        // CIColorMatrix unpremultiplies its input (colour / alpha) before applying the matrix, so forcing alpha
        // to 1 here *is* the normalisation: blurred background colour / blurred background weight.
        let normalised = blurredWeighted
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                         "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
            .applyingFilter("CIColorClamp")
        let plain = image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
        let confidence = blurredWeighted.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 4), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 4),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 4), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ]).applyingFilter("CIColorClamp")
        let blurred = normalised.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: plain, kCIInputMaskImageKey: confidence,
        ]).cropped(to: extent)
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred, kCIInputMaskImageKey: mask,
        ]).cropped(to: extent)
    }
}
