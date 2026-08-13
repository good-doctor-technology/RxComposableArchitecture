import TextureSwiftSupport

internal final class ListStoreCellNode: ASCellNode {
    internal let rootNode: ASDisplayNode

    // MARK: IOS27_LISTNODE_DEBUG (temporary)
    internal lazy var debugID: String = IOS27Debug.identity(self)

    private func debugLog(_ event: String, _ extra: [(String, String)] = []) {
        var f: [(String, String)] = []
        f.append(("supernode", supernode == nil ? "NIL" : IOS27Debug.identity(supernode!)))
        f.append(("isNodeLoaded", "\(isNodeLoaded)"))
        f.append(("frame", frame.dbg))
        f.append(("calcSize", calculatedSize.dbg))
        f.append(("interfaceState", "\(interfaceState.rawValue)"))
        f.append(("rootNode", IOS27Debug.identity(rootNode)))
        f.append(("rootNodeFrame", rootNode.frame.dbg))
        f.append(("rootNodeCalc", rootNode.calculatedSize.dbg))
        IOS27Debug.log(
            component: "ListStoreCellNode",
            instance: debugID,
            event: event,
            fields: f + extra
        )
    }

    internal init(rootNode: ASDisplayNode) {
        self.rootNode = rootNode
        super.init()
        automaticallyManagesSubnodes = true
        clipsToBounds = false
        debugLog("init")
    }

    deinit {
        IOS27Debug.log(
            component: "ListStoreCellNode",
            instance: debugID,
            event: "deinit"
        )
    }

    internal override func didLoad() {
        super.didLoad()
        debugLog("didLoad")
    }

    internal override func layoutSpecThatFits(_ constrainedSize: ASSizeRange) -> ASLayoutSpec {
        IOS27Debug.log(
            component: "ListStoreCellNode",
            instance: debugID,
            event: "layoutSpecThatFits",
            fields: [
                ("min", constrainedSize.min.dbg),
                ("max", constrainedSize.max.dbg),
                ("rootNode", IOS27Debug.identity(rootNode))
            ]
        )
        return ASWrapperLayoutSpec(layoutElement: rootNode)
    }

    internal override func calculateLayoutThatFits(_ constrainedSize: ASSizeRange) -> ASLayout {
        let layout = super.calculateLayoutThatFits(constrainedSize)
        IOS27Debug.log(
            component: "ListStoreCellNode",
            instance: debugID,
            event: "calculateLayoutThatFits",
            fields: [
                ("min", constrainedSize.min.dbg),
                ("max", constrainedSize.max.dbg),
                ("result", layout.size.dbg)
            ]
        )
        return layout
    }

    internal override func layout() {
        super.layout()
        debugLog("layout")
    }

    internal override func didEnterVisibleState() {
        super.didEnterVisibleState()
        debugLog("didEnterVisibleState")
    }

    internal override func didExitVisibleState() {
        super.didExitVisibleState()
        debugLog("didExitVisibleState")
    }
}

extension ASCellNode {
    internal static var emptyCell: ASCellNode {
        let cellNode = ASCellNode()
        cellNode.style.preferredSize = CGSize(width: 0.01, height: 0.01)
        IOS27Debug.log(
            component: "ListStoreNodeProxy",
            instance: "-",
            event: "RETURNED_EMPTY_CELL",
            fields: [("warning", "dataSource returned emptyCell - index out of range")]
        )
        return cellNode
    }
}
