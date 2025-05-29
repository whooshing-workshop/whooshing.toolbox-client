import Testing
@testable import WhooshingClient

struct ProgressTests {
    @Test("Progress 指定次数和步长")
    func testPiecesChunkProgress() throws {
        let step: UInt = 5
        let chunk: UInt = 1000
        let totalSize = step * chunk
        
        var seen: [ProgressContext] = []

        for ctx in Progress(pieces: step, chunk: chunk) {
            print(ctx)
            seen.append(ctx)
        }

        #expect(seen.count == step)
        #expect(seen.last?.done == true)

        for (i, ctx) in seen.enumerated() {
            #expect(ctx.index == i)
            #expect(ctx.curBytes == UInt(i + 1) * chunk)
            #expect(ctx.bytes <= chunk)
        }

        #expect(seen.last?.curBytes == Int(totalSize))
    }
    
    @Test("Progress 指定次数和总大小")
    func testPiecesBytesProgress() throws {
        let step: UInt = 7
        let totalSize: UInt = 7012
        let chunk = totalSize / (step - 1)
        
        var seen: [ProgressContext] = []

        for ctx in try! Progress(pieces: step, bytes: totalSize) {
            print(ctx)
            seen.append(ctx)
        }

        #expect(seen.count == step)
        #expect(seen.last?.done == true)

        for (i, ctx) in seen.enumerated() {
            #expect(ctx.index == i)
            if i < (seen.count - 1) {
                #expect(ctx.curBytes == UInt(i + 1) * chunk)
            }
            #expect(ctx.bytes <= chunk)
        }

        #expect(seen.last?.curBytes == Int(totalSize))
    }
    
    @Test("Progress 指定步长和总大小")
    func testChunkBytesProgress() throws {
        let totalSize: UInt = 8888
        let chunk: UInt = 1000
        let step = totalSize / chunk + 1
        
        var seen: [ProgressContext] = []

        for ctx in Progress(chunk: chunk, bytes: totalSize) {
            print(ctx)
            seen.append(ctx)
        }

        #expect(seen.count == step)
        #expect(seen.last?.done == true)

        for (i, ctx) in seen.enumerated() {
            #expect(ctx.index == i)
            if i < (seen.count - 1) {
                #expect(ctx.curBytes == UInt(i + 1) * chunk)
            }
            #expect(ctx.bytes <= chunk)
        }

        #expect(seen.last?.curBytes == Int(totalSize))
    }
    
    @Test("Progress 指定次数和总大小 抛错测试")
    func testPiecesBytesThrowingProgress() throws {
        #expect(throws: Error.self, performing: {
            try Progress(pieces: 5, bytes: 5012)
        })
        
        #expect(throws: Error.self, performing: {
            try Progress(pieces: 0, bytes: 1000)
        })
        
        #expect(throws: Error.self, performing: {
            try Progress(pieces: 8, bytes: 700)
        })
    }
}
