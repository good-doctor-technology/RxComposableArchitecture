import XCTest
import TextureSwiftSupport

@testable import RxComposableArchitecture

/// Regression test for iOS 27 rendering fix.
///
/// ASCollectionNode has zero intrinsic size. Without both `flexGrow` and `flexShrink`,
/// Texture's stack layout cannot properly allocate space to the node, resulting in a
/// 0x0 frame on iOS 27 due to changes in window geometry timing.
internal final class ListStoreNodeFlexPropertiesTests: XCTestCase {
    
    // MARK: - Flex Properties
    
    internal func test_listStoreNode_hasFlexGrowAndFlexShrink() {
        let (_, listNode) = makeListStoreNode()
        
        XCTAssertEqual(listNode.style.flexGrow, 1, "ListStoreNode must have flexGrow = 1 to fill available space")
        XCTAssertEqual(listNode.style.flexShrink, 1, "ListStoreNode must have flexShrink = 1 for Texture's optimized flex path")
    }
    
    internal func test_listStoreNode_receivesNonZeroLayout_inConstrainedStack() {
        let (_, listNode) = makeListStoreNode()
        
        // Simulate what happens when ListStoreNode is placed in a vertical stack
        // with a constrained parent (like a view controller's full-screen node)
        let parentNode = ASDisplayNode()
        parentNode.automaticallyManagesSubnodes = true
        parentNode.layoutSpecBlock = { _, constrainedSize in
            return ASWrapperLayoutSpec(layoutElement: listNode)
        }
        
        // Calculate layout with a typical screen size constraint
        let constrainedSize = ASSizeRange(
            min: CGSize(width: 375, height: 812),
            max: CGSize(width: 375, height: 812)
        )
        let layout = parentNode.calculateLayoutThatFits(constrainedSize)
        
        XCTAssertGreaterThan(layout.size.width, 0, "ListStoreNode should have non-zero width in constrained layout")
        XCTAssertGreaterThan(layout.size.height, 0, "ListStoreNode should have non-zero height in constrained layout")
    }
    
    internal func test_listStoreNode_receivesNonZeroLayout_inVerticalStack() {
        let (_, listNode) = makeListStoreNode()
        
        let headerNode = ASDisplayNode()
        headerNode.style.preferredSize = CGSize(width: 375, height: 100)
        
        let footerNode = ASDisplayNode()
        footerNode.style.preferredSize = CGSize(width: 375, height: 60)
        
        // Create a vertical stack similar to LoginViewController's layout
        let parentNode = ASDisplayNode()
        parentNode.automaticallyManagesSubnodes = true
        parentNode.layoutSpecBlock = { _, _ in
            return ASStackLayoutSpec(
                direction: .vertical,
                spacing: 0,
                justifyContent: .start,
                alignItems: .stretch,
                children: [headerNode, listNode, footerNode]
            )
        }
        
        // Calculate with a fixed screen-size constraint
        let constrainedSize = ASSizeRange(
            min: CGSize(width: 375, height: 812),
            max: CGSize(width: 375, height: 812)
        )
        let layout = parentNode.calculateLayoutThatFits(constrainedSize)
        
        // The list node should get the remaining space (812 - 100 - 60 = 652)
        let listLayout = layout.sublayouts.first { $0.layoutElement === listNode }
        XCTAssertNotNil(listLayout, "ListStoreNode should be present in layout sublayouts")
        
        if let listLayout = listLayout {
            XCTAssertEqual(listLayout.size.width, 375, "ListStoreNode should stretch to full width")
            XCTAssertEqual(listLayout.size.height, 652, accuracy: 1, "ListStoreNode should fill remaining vertical space")
        }
    }
    
    // MARK: - Helpers
    
    private func makeListStoreNode() -> (Store<AppState, AppAction>, ListStoreNode<[ChildState], ChildAction>) {
        let parentStore = Store(
            initialState: AppState(childs: [
                ChildState(id: 0, count: 0),
                ChildState(id: 1, count: 0)
            ]),
            reducer: appReducer,
            environment: ()
        )
        
        let childsStore = parentStore.scope(
            state: \.childs,
            action: AppAction.child(identifier:action:)
        )
        
        let listNode = ListStoreNode(
            store: childsStore,
            collectionViewLayout: UICollectionViewFlowLayout(),
            content: ChildNode.init
        )
        
        return (parentStore, listNode)
    }
}
