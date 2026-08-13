import RxCocoa
import RxSwift
import TextureSwiftSupport

/// An` ASCollectionNode` that will automatically be updated on state change.
public final class ListStoreNode<State, Action>: ASCollectionNode
where State: Collection,
      State: Equatable,
      State.Element: HashDiffable,
      State.Element: Equatable,
      Action: Equatable {
    private let store: Store<State, (State.Element.IdentifierType, Action)>
    private let id: KeyPath<State.Element, State.Element.IdentifierType>
    private let content: (Store<State.Element, Action>) -> ASDisplayNode
    
    private let disposeBag = DisposeBag()
    
    internal private(set) var items: [State.Element] = []
    internal private(set) var cellNodes: [ListStoreCellNode] = []
    
    private lazy var proxy = ListStoreNodeProxy(listStoreNode: self)
    
    /// Whether batch update should be animated. Default to `false`.
    public var shouldAnimateUpdate: Bool = false
    
    /// Schedules a block to be performed (on main thread) by the completion block of performBatchUpdates:.
    public var onDidCompleteUpdate: (Bool) -> Void = { _ in }
    
    public override var dataSource: ASCollectionDataSource? {
        didSet {
            if oldValue != nil {
                assertionFailure("The data source is already defined")
            }
        }
    }
    
    /**
     Init `ListStoreNode`
     
     - Parameters:
        - store: store that contains `Collection` of `ElementState` as state, and `(IdentifierType, Action)` as action.
        - id: keypath to HashDiffable identifier.
        - collectionViewLayout: layout information of the collection view.
        - content: set what node to use on `ListStoreNode`.
     
     ## Example where ChildState is Struct
     
     ```
     struct AppState {
        var childs: [ChildState]
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, id: \.id, collectionViewLayout: UICollectionViewFlowLayout()) {
        let childNode = ChildNode(with: store)
     
        // setup neccessary thing here, before node being passed to `ListStoreNode`
        ...
        ...
        childNode.backgroundColor = .white
     
        return childNode
     }
     ```
     
     ## Example where ChildState is Enum
     
     ```
     struct AppState {
        var childs: [ChildState]
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, id: \.id, collectionViewLayout: UICollectionViewFlowLayout()) { elementStore in
        SwitchCaseStoreNode(store: elementStore) { matcher in
            matcher.addMatch(
                state: /ChildState.caseA,
                action: ChildAction.caseA,
                createNode: { caseAStore in
                    CaseANode(store: caseAStore)
                }
            )
     
            matcher.addMatch(
                state: /ChildState.caseB,
                action: ChildAction.caseB,
                createNode: { caseBStore in
                    CaseBNode(store: caseBStore)
                }
            )
        }
     }
     ```
     */
    public init(
        store: Store<State, (State.Element.IdentifierType, Action)>,
        id: KeyPath<State.Element, State.Element.IdentifierType>,
        collectionViewLayout: UICollectionViewLayout = UICollectionViewFlowLayout(),
        content: @escaping (Store<State.Element, Action>) -> ASDisplayNode
    ) {
        self.store = store
        self.id = id
        self.content = content
        super.init(
            frame: .zero,
            collectionViewLayout: collectionViewLayout,
            layoutFacilitator: nil
        )
        
        dataSource = proxy
        style.flexGrow = 1

        IOS27Debug.log(
            component: "ListStoreNode",
            instance: debugID,
            event: "init",
            fields: [
                ("flexGrow", "\(style.flexGrow)"),
                ("layoutClass", "\(type(of: collectionViewLayout))")
            ]
        )
    }

    // MARK: IOS27_LISTNODE_DEBUG (temporary)

    /// Stable short id so instances can be told apart across lifecycle cycles.
    internal lazy var debugID: String = IOS27Debug.identity(self)

    deinit {
        IOS27Debug.log(
            component: "ListStoreNode",
            instance: debugID,
            event: "deinit",
            fields: [("itemCount", "\(items.count)"), ("cellNodeCount", "\(cellNodes.count)")]
        )
    }

    /// Snapshot of everything relevant to the zero-frame bug.
    /// NOTE: never touches `view` unless already loaded, so it cannot itself
    /// force view creation and change behaviour.
    internal func debugFields(_ extra: [(String, String)] = []) -> [(String, String)] {
        var f: [(String, String)] = []
        f.append(("supernode", supernode == nil ? "NIL" : IOS27Debug.identity(supernode!)))
        f.append(("isNodeLoaded", "\(isNodeLoaded)"))
        f.append(("frame", frame.dbg))
        f.append(("bounds", bounds.dbg))
        f.append(("calcSize", calculatedSize.dbg))
        f.append(("interfaceState", "\(interfaceState.rawValue)"))
        f.append(("inHierarchy", "\(isInHierarchy)"))
        f.append(("visible", "\(isVisible)"))
        f.append(("flexGrow", "\(style.flexGrow)"))
        f.append(("flexShrink", "\(style.flexShrink)"))
        f.append(("prefSize", style.preferredSize.dbg))
        f.append(("items", "\(items.count)"))
        f.append(("cellNodes", "\(cellNodes.count)"))
        f.append(("dataSourceSet", "\(dataSource != nil)"))

        if isNodeLoaded, Thread.isMainThread {
            let cv = view
            f.append(("cv.frame", cv.frame.dbg))
            f.append(("cv.bounds", cv.bounds.dbg))
            f.append(("cv.contentSize", cv.contentSize.dbg))
            f.append(("cv.superview", cv.superview == nil ? "NIL" : "\(type(of: cv.superview!))"))
            f.append(("cv.window", cv.window == nil ? "NIL" : "set"))
            f.append(("cv.sections", "\(cv.numberOfSections)"))
            f.append(("cv.hidden", "\(cv.isHidden)"))
            f.append(("cv.alpha", "\(cv.alpha)"))
        }

        return f + extra
    }

    private func debugLog(_ event: String, _ extra: [(String, String)] = []) {
        IOS27Debug.log(
            component: "ListStoreNode",
            instance: debugID,
            event: event,
            fields: debugFields(extra)
        )
    }
    
    /**
     Init `ListStoreNode` with Never as childs action
     
     Recommended to use `IdentifiedArray`, as the performance accessing random index on the collection is much better compare to plain array.
     - Parameters:
        - store: store that contains `Collection` of `ElementState` as state, and `Never` as action.
        - id: keypath to `HashDiffable` identifier
        - collectionViewLayout: layout information of the collection view.
        - content: set what node to use on `ListStoreNode`.
     
     ## Example
     
     ```
     struct AppState {
        var childs: [ChildState] or IdentifiedArrayOf<ChildState>
     }
     
     let store = store.scope(state: \AppState.childs).actionless
     
     let node = ListStoreNode(store: store) {
         let childNode = ChildNode(with: store)
     
         // setup neccessary thing here, before node being passed to `ListStoreNode`
         ...
         ...
         childNode.backgroundColor = .baseWhite
         return childNode
     }
     ```
     */
    public convenience init(
        store: Store<State, Never>,
        collectionViewLayout: UICollectionViewLayout = UICollectionViewFlowLayout(),
        content: @escaping (Store<State.Element, Action>) -> ASDisplayNode
    ) where Action == Never {
        func noAction<A>(id: State.Element.IdentifierType, action: Never) -> A {}
        
        self.init(
            store: store.scope(
                state: { $0 },
                action: noAction
            ),
            id: \.id,
            collectionViewLayout: collectionViewLayout,
            content: content
        )
    }
    
    /**
     Init `ListStoreNode`
     
     - Parameters:
        - store: store that contains `Collection` of `ElementState` as state, and `(IdentifierType, Action)` as action.
        - id: keypath to HashDiffable identifier.
        - collectionViewLayout: layout information of the collection view.
        - content: set what node to use on `ListStoreNode`.
     
     ## Example where ChildState is Struct
     
     ```
     struct AppState {
        var childs: IdentifiedArrayOf<ChildState>
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, id: \.id, collectionViewLayout: UICollectionViewFlowLayout()) {
        let childNode = ChildNode(with: store)
     
        // setup neccessary thing here, before node being passed to `ListStoreNode`
        ...
        ...
        childNode.backgroundColor = .baseWhite
     
        return childNode
     }
     ```
     
     ## Example where ChildState is Enum
     
     ```
     struct AppState {
        var childs: IdentifiedArrayOf<ChildState>
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, id: \.id, collectionViewLayout: UICollectionViewFlowLayout()) { elementStore in
        SwitchCaseStoreNode(store: elementStore) { matcher in
            matcher.addMatch(
                state: /ChildState.caseA,
                action: ChildAction.caseA,
                createNode: { caseAStore in
                    CaseANode(store: caseAStore)
                }
            )
     
            matcher.addMatch(
                state: /ChildState.caseB,
                action: ChildAction.caseB,
                createNode: { caseBStore in
                    CaseBNode(store: caseBStore)
                }
            )
        }
     }
     ```
     */
    public convenience init(
        store: Store<IdentifiedArrayOf<State.Element>, (State.Element.IdentifierType, Action)>,
        id: KeyPath<State.Element, State.Element.IdentifierType>,
        collectionViewLayout: UICollectionViewLayout = UICollectionViewFlowLayout(),
        content: @escaping (Store<State.Element, Action>) -> ASDisplayNode
    ) {
        self.init(
            store: store.scope(
                state: { $0.elements as! State }
            ),
            id: id,
            collectionViewLayout: collectionViewLayout,
            content: content
        )
    }
    
    /**
     Init `ListStoreNode`
     
     - Parameters:
        - store: store that contains `Collection` of `ElementState` as state, and `(IdentifierType, Action)` as action.
        - collectionViewLayout: layout information of the collection view.
        - content: set what node to use on `ListStoreNode`.
     
     ## Example where ChildState is Struct
     
     ```
     struct AppState {
        var childs: [ChildState]
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, collectionViewLayout: UICollectionViewFlowLayout()) {
        let childNode = ChildNode(with: store)
     
        // setup neccessary thing here, before node being passed to `ListStoreNode`
        ...
        ...
        childNode.backgroundColor = .baseWhite
     
        return childNode
     }
     ```
     
     ## Example where ChildState is Enum
     
     ```
     struct AppState {
        var childs: [ChildState]
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, collectionViewLayout: UICollectionViewFlowLayout()) { elementStore in
        SwitchCaseStoreNode(store: elementStore) { matcher in
            matcher.addMatch(
                state: /ChildState.caseA,
                action: ChildAction.caseA,
                createNode: { caseAStore in
                    CaseANode(store: caseAStore)
                }
            )
     
            matcher.addMatch(
                state: /ChildState.caseB,
                action: ChildAction.caseB,
                createNode: { caseBStore in
                    CaseBNode(store: caseBStore)
                }
            )
        }
     }
     ```
     */
    public convenience init(
        store: Store<State, (State.Element.IdentifierType, Action)>,
        collectionViewLayout: UICollectionViewLayout = UICollectionViewFlowLayout(),
        content: @escaping (Store<State.Element, Action>) -> ASDisplayNode
    ) {
        self.init(
            store: store,
            id: \.id,
            collectionViewLayout: collectionViewLayout,
            content: content
        )
    }
    
    /**
     Init `ListStoreNode`
     
     - Parameters:
        - store: store that contains `Collection` of `ElementState` as state, and `(IdentifierType, Action)` as action.
        - id: keypath to HashDiffable identifier.
        - collectionViewLayout: layout information of the collection view.
        - content: set what node to use on `ListStoreNode`.
     
     ## Example where ChildState is Struct
     
     ```
     struct AppState {
        var childs: IdentifiedArrayOf<ChildState>
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, collectionViewLayout: UICollectionViewFlowLayout()) {
        let childNode = ChildNode(with: store)
     
        // setup neccessary thing here, before node being passed to `ListStoreNode`
        ...
        ...
        childNode.backgroundColor = .baseWhite
     
        return childNode
     }
     ```
     
     ## Example where ChildState is Enum
     
     ```
     struct AppState {
        var childs: IdentifiedArrayOf<ChildState>
     }
     
     enum AppAction {
        case child(identifier: String, action: ChildAction)
     }
     
     let store = store.scope(
        state: \AppState.childs,
        action: AppAction.child(identifier:action:)
     )
     
     let node = ListStoreNode(store: store, collectionViewLayout: UICollectionViewFlowLayout()) { elementStore in
        SwitchCaseStoreNode(store: elementStore) { matcher in
            matcher.addMatch(
                state: /ChildState.caseA,
                action: ChildAction.caseA,
                createNode: { caseAStore in
                    CaseANode(store: caseAStore)
                }
            )
     
            matcher.addMatch(
                state: /ChildState.caseB,
                action: ChildAction.caseB,
                createNode: { caseBStore in
                    CaseBNode(store: caseBStore)
                }
            )
        }
     }
     ```
     */
    public convenience init(
        store: Store<IdentifiedArrayOf<State.Element>, (State.Element.IdentifierType, Action)>,
        collectionViewLayout: UICollectionViewLayout = UICollectionViewFlowLayout(),
        content: @escaping (Store<State.Element, Action>) -> ASDisplayNode
    ) {
        self.init(
            store: store,
            id: \.id,
            collectionViewLayout: collectionViewLayout,
            content: content
        )
    }
    
    public override func didLoad() {
        super.didLoad()
        
        // Set Identifier to ASCollectionView for Monitoring
        view.accessibilityIdentifier = "ListStoreNode-\(closestViewController?.description ?? "")"

        debugLog("didLoad", [
            ("closestVC", closestViewController == nil ? "NIL" : "\(type(of: closestViewController!))")
        ])

        store.observable
            .throttle(.milliseconds(100), scheduler: MainScheduler.instance)
            .distinctUntilChanged { lhs, rhs -> Bool in
                guard lhs.count == rhs.count else { return false }
                return zip(lhs, rhs).allSatisfy { $0.id == $1.id }
            }
            .asDriver { _ in .empty() }
            .drive(onNext: { [weak self] newItems in
                guard let self = self else { return }

                IOS27Debug.log(
                    component: "ListStoreNode",
                    instance: self.debugID,
                    event: "store.emit",
                    fields: [("newCount", "\(newItems.count)"), ("currentItems", "\(self.items.count)")]
                )

                if let newItems = newItems as? [State.Element] {
                    self.performUpdates(newItems: newItems)
                } else if let newItems = newItems as? IdentifiedArrayOf<State.Element> {
                    self.performUpdates(newItems: newItems.elements)
                }
            })
            .disposed(by: disposeBag)
    }

    // MARK: Lifecycle instrumentation (IOS27_LISTNODE_DEBUG)

    public override func didEnterHierarchy() {
        super.didEnterHierarchy()
        debugLog("didEnterHierarchy")
    }

    public override func didExitHierarchy() {
        super.didExitHierarchy()
        debugLog("didExitHierarchy")
    }

    public override func interfaceStateDidChange(
        _ newState: ASInterfaceState,
        from oldState: ASInterfaceState
    ) {
        super.interfaceStateDidChange(newState, from: oldState)
        debugLog("interfaceStateDidChange", [
            ("from", "\(oldState.rawValue)"),
            ("to", "\(newState.rawValue)")
        ])
    }

    public override func didEnterPreloadState() {
        super.didEnterPreloadState()
        debugLog("didEnterPreloadState")
    }

    public override func didExitPreloadState() {
        super.didExitPreloadState()
        debugLog("didExitPreloadState")
    }

    public override func didExitVisibleState() {
        super.didExitVisibleState()
        debugLog("didExitVisibleState")
    }

    public override func didExitDisplayState() {
        super.didExitDisplayState()
        debugLog("didExitDisplayState")
    }

    public override func layout() {
        super.layout()
        debugLog("layout")
    }

    public override func calculateLayoutThatFits(_ constrainedSize: ASSizeRange) -> ASLayout {
        let layout = super.calculateLayoutThatFits(constrainedSize)
        IOS27Debug.log(
            component: "ListStoreNode",
            instance: debugID,
            event: "calculateLayoutThatFits",
            fields: [
                ("min", constrainedSize.min.dbg),
                ("max", constrainedSize.max.dbg),
                ("result", layout.size.dbg),
                ("flexGrow", "\(style.flexGrow)"),
                ("flexShrink", "\(style.flexShrink)")
            ]
        )
        return layout
    }
    
    public override func didEnterDisplayState() {
        super.didEnterDisplayState()
        debugLog("didEnterDisplayState")
        // On iOS 26+, when the ASCollectionNode's view is force-loaded before
        // entering the hierarchy (a common pattern for crash-safety), the
        // UICollectionView may not properly trigger its layout cycle once it
        // finally appears on screen. Force a full reloadData here to ensure the
        // collection view re-queries its data source and renders cells.
        ensureCollectionViewRendered()
    }
    
    public override func didEnterVisibleState() {
        super.didEnterVisibleState()
        debugLog("didEnterVisibleState")
        // On iOS 26+, when returning from background or navigating back to a
        // screen with a ListStoreNode, the UICollectionView may have stale
        // internal state. Force a reload on becoming visible.
        ensureCollectionViewRendered()
    }
    
    private func ensureCollectionViewRendered() {
        guard isNodeLoaded, !items.isEmpty else {
            debugLog("ensureCollectionViewRendered.SKIPPED", [
                ("reason", !isNodeLoaded ? "nodeNotLoaded" : "itemsEmpty")
            ])
            return
        }
        // Always force a full reload to ensure UICollectionView re-queries
        // its data source. This handles both the initial load case and the
        // return-from-background case on iOS 26+.
        debugLog("ensureCollectionViewRendered.WILL_RELOAD")
        reloadData()
    }
    
    private func performUpdates(newItems: [State.Element]) {
        assertMainThread("performUpdates")
        
        let oldItemsForDiffing: [AnyHashDiffable] = items.map(AnyHashDiffable.init)
        let newItemsForDiffing: [AnyHashDiffable] = newItems.map(AnyHashDiffable.init).removeDuplicates()
        
        let updatedItems = newItemsForDiffing.compactMap { $0.base as? State.Element }

        debugLog("performUpdates.enter", [
            ("oldCount", "\(oldItemsForDiffing.count)"),
            ("newCount", "\(newItemsForDiffing.count)")
        ])

        // On iOS 26+, UICollectionView enforces stricter data source consistency
        // during performBatchUpdates. When going from empty → populated (initial load),
        // use reloadData instead of batch updates to avoid the timing issue where the
        // collection view has not yet completed its initial internal reloadData.
        if oldItemsForDiffing.isEmpty && !newItemsForDiffing.isEmpty {
            items = updatedItems
            debugLog("performUpdates.branch=EMPTY_TO_POPULATED_reloadData")
            reloadData()
            return
        }
        
        // For empty → empty, no-op
        if newItemsForDiffing.isEmpty && oldItemsForDiffing.isEmpty {
            debugLog("performUpdates.branch=EMPTY_TO_EMPTY_noop")
            return
        }
        
        let listDiff: DiffingInterfaceList.Result = DiffingInterfaceList.diffing(
            oldArray: oldItemsForDiffing,
            newArray: newItemsForDiffing
        )
        
        let deletes: IndexSet = listDiff.deletes
        let inserts: IndexSet = listDiff.inserts
        let moves: [DiffingInterfaceList.MoveIndex] = listDiff.moves
        
        // Compute new cell nodes before the batch update, but don't assign yet.
        // The data source must return the old count when the collection view reads
        // numberOfSections at the start of performBatch (iOS 26+ enforces this).
        let updatedCellNodes = diffingCellNode(newItems: newItemsForDiffing, diff: listDiff)
        
        performBatch(
            animated: shouldAnimateUpdate,
            updates: { [weak self] in
                guard let self = self else { return }
                // Update the backing data inside the updates block so the data source
                // returns the correct "after" count when the collection view validates
                // at endUpdates time.
                self.items = updatedItems
                self.cellNodes = updatedCellNodes
                
                self.deleteSections(deletes)
                self.insertSections(inserts)
                moves.forEach { self.moveSection($0.from, toSection: $0.to) }
            },
            completion: onDidCompleteUpdate
        )
    }
    
    private func diffingCellNode(newItems: [AnyHashDiffable], diff: DiffingInterfaceList.Result) -> [ListStoreCellNode] {
        /* The Order of updating collection must followed the rule like this:
           - Create a mutable copy A1
           - Do all reloads (But we do not do it here, because Store will handle that)
           - Delete from array A1 in descending order
           - Perform inserts in ascending order
           - Move from array A into A1
         https://github.com/Instagram/IGListKit/issues/1006#issuecomment-342579413
         */
        
        var copyCellNodes = cellNodes
        
        diff.deletes.sorted(by: >).forEach { index in
            copyCellNodes.remove(at: index)
        }
        
        diff.inserts.sorted(by: <).forEach { index in
            guard
                newItems.indices.contains(index),
                let stateElement = newItems[index].base as? State.Element,
                let elementStore = store.scope(
                    at: stateElement[keyPath: id],
                    action: { [id] action in
                        (stateElement[keyPath: id], action)
                    }
                )
            else { return }
            
            let cellNode = createCellNode(store: elementStore)
            copyCellNodes.insert(cellNode, at: index)
        }
        
        // ListDiff moves return a pair items intead a single item thus we can't use swap operation
        // in order to achieve the moves, we need to delete `from` index and insert object in `to` index
        let fromMoves = diff.moves.map(\.to).sorted(by: >)
        fromMoves.forEach { index in
            if copyCellNodes.count > index {
                copyCellNodes.remove(at: index)
            } else {
                assertItemIndexNotFound("diffingListCellNodes-move-delete", index)
            }
        }
        
        diff.moves.forEach { move in
            if cellNodes.indices.contains(move.from) {
                if copyCellNodes.count + 1 > move.to {
                    copyCellNodes.insert(cellNodes[move.from], at: move.to)
                } else {
                    assertItemIndexNotFound("diffingListCellNodes-move-insert-item", move.to)
                }
            } else {
                assertItemIndexNotFound("diffingListCellNodes-move-insert-safeindex", move.from)
            }
        }
        
        return copyCellNodes
    }
    
    private func createCellNode(store: Store<State.Element, Action>) -> ListStoreCellNode {
        let node = content(store)
        return ListStoreCellNode(rootNode: node)
    }
    
    public override func reloadData() {
        assertMainThread("reloadData")

        let previousCellNodeIDs = cellNodes.map { IOS27Debug.identity($0) }.joined(separator: ",")

        cellNodes = items
            .compactMap { [id] item -> Store<State.Element, Action>? in
                store.scope(
                    at: item[keyPath: id],
                    action: { [id] action in
                        (item[keyPath: id], action)
                    }
                )
            }
            .map(createCellNode)

        let newCellNodeIDs = cellNodes.map { IOS27Debug.identity($0) }.joined(separator: ",")

        debugLog("reloadData.RECREATED_CELL_NODES", [
            ("oldCellNodeIDs", previousCellNodeIDs.isEmpty ? "none" : previousCellNodeIDs),
            ("newCellNodeIDs", newCellNodeIDs.isEmpty ? "none" : newCellNodeIDs)
        ])

        super.reloadData()
        view.collectionViewLayout.invalidateLayout()

        debugLog("reloadData.AFTER_INVALIDATE")
    }
    
    /**
     Getter current view based on respective id
     
     - Parameters:
        - id: element `IdentifierType`
     - Returns: A Node
     */
    public func subnode(id: State.Element.IdentifierType) -> ASDisplayNode? {
        guard
            let index = items.firstIndex(where: { $0.id == id })
        else { return nil }
        
        return cellNodes[safe: index]?.rootNode
    }
}

/// Proxy for ListStoreNode that stores data source and delegates
private class ListStoreNodeProxy<State, Action>: NSObject, ASCollectionDataSource
where State: Collection,
      State: Equatable,
      State.Element: Equatable,
      State.Element: HashDiffable,
      Action: Equatable {
    private weak var listStoreNode: ListStoreNode<State, Action>?
    
    fileprivate init(listStoreNode: ListStoreNode<State, Action>) {
        self.listStoreNode = listStoreNode
        super.init()
    }
    
    // MARK: Collection Data Sources
    
    fileprivate func numberOfSections(in _: ASCollectionNode) -> Int {
        guard let listStoreNode = listStoreNode else {
            IOS27Debug.log(
                component: "ListStoreNodeProxy",
                instance: "-",
                event: "numberOfSections.NODE_DEALLOCATED",
                fields: [("returned", "0")]
            )
            return 0
        }
        let count = listStoreNode.cellNodes.count
        IOS27Debug.log(
            component: "ListStoreNodeProxy",
            instance: listStoreNode.debugID,
            event: "numberOfSections",
            fields: [("returned", "\(count)"), ("items", "\(listStoreNode.items.count)")]
        )
        return count
    }
    
    fileprivate func collectionNode(_: ASCollectionNode, numberOfItemsInSection _: Int) -> Int {
        return 1
    }
    
    fileprivate func collectionNode(_: ASCollectionNode, nodeForItemAt indexPath: IndexPath) -> ASCellNode {
        let node = listStoreNode?.cellNodes[safe: indexPath.section]
        IOS27Debug.log(
            component: "ListStoreNodeProxy",
            instance: listStoreNode?.debugID ?? "-",
            event: "nodeForItemAt",
            fields: [
                ("section", "\(indexPath.section)"),
                ("found", node == nil ? "NO->emptyCell" : "YES"),
                ("cellNodeID", node.map { IOS27Debug.identity($0) } ?? "-")
            ]
        )
        return node ?? .emptyCell
    }
}
