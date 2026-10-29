//
//  measureTabBar.swift
//  winston
//
//  Created by Igor Marcossi on 09/12/23.
//

import SwiftUI

struct TabBarMeasurerAccessor: UIViewControllerRepresentable {
  var setTabBarHeight: (Double) -> Void
  private let proxyController = ViewController()
  
  func makeUIViewController(context: UIViewControllerRepresentableContext<TabBarMeasurerAccessor>) -> UIViewController {
    proxyController.callback = setTabBarHeight
    return proxyController
  }
  
  func updateUIViewController(_ uiViewController: UIViewController, context: UIViewControllerRepresentableContext<TabBarMeasurerAccessor>) { }
  
  typealias UIViewControllerType = UIViewController
  
  private class ViewController: UIViewController {
    var callback: (Double) -> Void = { _ in }
    private var lastReported: Double?
    
    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      report()
    }
    
    // Folding iPhone Duo or resizing a window can move the tab bar.
    override func viewDidLayoutSubviews() {
      super.viewDidLayoutSubviews()
      report()
    }
    
    /// The tab bar's height above the bottom safe area, or 0 when it isn't a horizontal bar
    /// along the bottom of the window: iPad and unfolded iPhone Duo show it at the top, folded
    /// iPhone Duo down the side.
    private func report() {
      guard let tabBar = tabBarController?.tabBar, let window = tabBar.window else { return }
      let frame = tabBar.convert(tabBar.bounds, to: window)
      let alongBottom = !tabBar.isHidden && frame.width >= window.bounds.width * 0.8 && frame.maxY >= window.bounds.maxY - 1
      let height = alongBottom ? max(0, frame.height - window.safeAreaInsets.bottom) : 0
      guard height != lastReported else { return }
      lastReported = height
      DispatchQueue.main.async { self.callback(height) }
    }
  }
}

extension View {
  func measureTabBar(_ setTabBarHeight: @escaping (Double) -> Void) -> some View {
    self
      .background(TabBarMeasurerAccessor(setTabBarHeight: setTabBarHeight).allowsHitTesting(false))
  }
}
