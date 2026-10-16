//
//  VoiceChain.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import Accelerate

struct VoiceChain {
    var filters: [Biquad]
    var pregain = 0.0
    var compressor: Compressor?
    var gain = 0.0

    static func equalizer(rate: Double = Double(VoiceEnhancer.rate)) -> [Biquad] {
        [.highPass(80, q: 0.707, rate: rate),
         .peaking(300, gain: -2, q: 1, rate: rate),
         .peaking(3200, gain: 2, q: 0.8, rate: rate),
         .highShelf(10000, gain: 1.5, rate: rate)]
    }

    mutating func process(_ p: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in filters.indices { filters[i].process(p, n) }
        if pregain != 0 { scale(p, n, pregain) }
        compressor?.process(p, n)
        if gain != 0 { scale(p, n, gain) }
    }

    private func scale(_ p: UnsafeMutablePointer<Float>, _ n: Int, _ db: Double) {
        var k = Float(pow(10, db / 20))
        vDSP_vsmul(p, 1, &k, p, 1, vDSP_Length(n))
    }
}

struct Biquad {
    var b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    init(b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        (self.b0, self.b1, self.b2, self.a1, self.a2) = (b0, b1, b2, a1, a2)
    }

    private init(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) {
        self.init(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }

    static func highPass(_ f: Double, q: Double, rate: Double) -> Biquad {
        let w = 2 * Double.pi * f / rate, c = cos(w), alpha = sin(w) / (2 * q)
        return Biquad((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha)
    }

    static func peaking(_ f: Double, gain: Double, q: Double, rate: Double) -> Biquad {
        let a = pow(10, gain / 40), w = 2 * Double.pi * f / rate, c = cos(w), alpha = sin(w) / (2 * q)
        return Biquad(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    }

    static func highShelf(_ f: Double, gain: Double, slope: Double = 1, rate: Double) -> Biquad {
        let a = pow(10, gain / 40), w = 2 * Double.pi * f / rate, c = cos(w)
        let alpha = sin(w) / 2 * sqrt((a + 1 / a) * (1 / slope - 1) + 2), r = 2 * sqrt(a) * alpha
        return Biquad(a * ((a + 1) + (a - 1) * c + r), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - r),
                      (a + 1) - (a - 1) * c + r, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - r)
    }

    mutating func process(_ p: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0 ..< n {
            let x = Double(p[i])
            let y = b0 * x + z1
            z1 = b1 * x - a1 * y + z2
            z2 = b2 * x - a2 * y
            p[i] = Float(y)
        }
    }
}

struct LoudnessMeter {
    private var shelf = Biquad(b0: 1.53512485958697, b1: -2.69169618940638, b2: 1.19839281085285,
                               a1: -1.69065929318241, a2: 0.73248077421585)
    private var highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: -1.99004745483398, a2: 0.99007225036621)
    private var steps: [Double] = []
    private var sum = 0.0, count = 0
    private var scratch = [Float]()
    private static let step = VoiceEnhancer.rate / 10

    mutating func add(_ p: UnsafePointer<Float>, _ n: Int) {
        if scratch.count < n { scratch = [Float](repeating: 0, count: n) }
        scratch.withUnsafeMutableBufferPointer { s in
            s.baseAddress!.update(from: p, count: n)
            shelf.process(s.baseAddress!, n)
            highPass.process(s.baseAddress!, n)
            for i in 0 ..< n {
                let y = Double(s[i])
                sum += y * y
                count += 1
                if count == Self.step {
                    steps.append(sum / Double(count))
                    sum = 0
                    count = 0
                }
            }
        }
    }

    var integrated: Double? {
        guard steps.count >= 4 else { return nil }
        let blocks = (0 ... steps.count - 4).map { (j: Int) -> Double in
            let sum: Double = steps[j] + steps[j + 1] + steps[j + 2] + steps[j + 3]
            return sum / 4
        }
        func lufs(_ z: Double) -> Double { -0.691 + 10 * log10(max(z, 1e-20)) }
        let audible = blocks.filter { lufs($0) > -70 }
        guard !audible.isEmpty else { return nil }
        let relative = lufs(audible.reduce(0, +) / Double(audible.count)) - 10
        let gated = audible.filter { lufs($0) > relative }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }
}

struct Compressor {
    var threshold = -22.0, ratio = 2.0, knee = 6.0
    private var power = 0.0
    private var reduction = 0.0
    private let detector: Double, attack: Double, release: Double

    init(rate: Double = Double(VoiceEnhancer.rate)) {
        detector = exp(-1 / (0.010 * rate))
        attack = exp(-1 / (0.005 * rate))
        release = exp(-1 / (0.150 * rate))
    }

    func curve(_ level: Double) -> Double {
        let over = level - threshold
        if 2 * over < -knee { return 0 }
        if 2 * abs(over) <= knee { return (1 / ratio - 1) * pow(over + knee / 2, 2) / (2 * knee) }
        return (1 / ratio - 1) * over
    }

    mutating func process(_ p: UnsafeMutablePointer<Float>, _ n: Int) {
        for i in 0 ..< n {
            let x = Double(p[i])
            power = detector * power + (1 - detector) * x * x
            let target = curve(10 * log10(power + 1e-12))
            let k = target < reduction ? attack : release
            reduction = k * reduction + (1 - k) * target
            if reduction < -0.001 { p[i] = Float(x * pow(10, reduction / 20)) }
        }
    }
}

struct LookaheadLimiter {
    let ceiling: Float
    let latency: Int
    private let recovery: Float
    private var delay: [Float]
    private var delayIndex = 0
    private var ramp: [Float]
    private var rampIndex = 0
    private var rampSum: Double
    private var held: Float = 1
    private var dequeIndex: [Int], dequeGain: [Float]
    private var front = 0, size = 0
    private var n = 0

    init(ceiling: Float = 0.891, lookahead: Int = 96, release: Double = 0.05, rate: Double = Double(VoiceEnhancer.rate)) {
        self.ceiling = ceiling
        latency = lookahead
        recovery = Float(1 - exp(-1 / (release * rate)))
        delay = [Float](repeating: 0, count: lookahead)
        ramp = [Float](repeating: 1, count: lookahead + 1)
        rampSum = Double(lookahead + 1)
        dequeIndex = [Int](repeating: 0, count: lookahead + 2)
        dequeGain = [Float](repeating: 1, count: lookahead + 2)
    }

    mutating func process(_ p: UnsafeMutablePointer<Float>, _ count: Int) {
        let cap = dequeIndex.count, window = latency + 1
        for i in 0 ..< count {
            let x = p[i], level = abs(x)
            let need: Float = level > ceiling ? ceiling / level : 1
            while size > 0, dequeGain[(front + size - 1) % cap] >= need { size -= 1 }
            dequeIndex[(front + size) % cap] = n
            dequeGain[(front + size) % cap] = need
            size += 1
            while dequeIndex[front] <= n - window {
                front = (front + 1) % cap
                size -= 1
            }
            let lowest = dequeGain[front]
            held = lowest < held ? lowest : held + (lowest - held) * recovery
            rampSum += Double(held - ramp[rampIndex])
            ramp[rampIndex] = held
            rampIndex = (rampIndex + 1) % window
            let gain = Float(rampSum / Double(window))
            let out = delay[delayIndex]
            delay[delayIndex] = x
            delayIndex = (delayIndex + 1) % latency
            p[i] = min(max(out * gain, -ceiling), ceiling)
            n += 1
        }
    }
}
