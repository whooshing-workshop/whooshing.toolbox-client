import NIOExtras
import NIOCore

extension LengthFieldPrepender: @retroactive @unchecked Sendable {}

extension ByteToMessageHandler: @retroactive @unchecked Sendable {}
