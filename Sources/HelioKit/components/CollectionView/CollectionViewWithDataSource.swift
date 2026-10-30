//
//  CollectionViewWithDataSource.swift
//  Helio
//
//  Created by Igor Marcossi on 14/04/24.
//

import SwiftUI

final class CollectionViewWithDataSource<SectionIdentifierType: Hashable & Sendable, ItemIdentifierType: Hashable & Sendable>: UICollectionView {
  typealias DataSource = UICollectionViewDiffableDataSource<SectionIdentifierType, ItemIdentifierType>
  typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIdentifierType, ItemIdentifierType>

  private let cellProvider: DataSource.CellProvider

  private let updateQueue: DispatchQueue = .init(
    label: "com.collectionview.update",
    qos: .userInteractive,
  )

  private lazy var collectionDataSource: DataSource = .init(
    collectionView: self,
    cellProvider: cellProvider,
  )

  init(frame: CGRect,
       collectionViewLayout: UICollectionViewLayout,
       collectionViewConfiguration: (UICollectionView) -> Void,
       cellProvider: @escaping DataSource.CellProvider,
       supplementaryViewProvider: DataSource.SupplementaryViewProvider?)
  {
    self.cellProvider = cellProvider
    super.init(frame: frame, collectionViewLayout: collectionViewLayout)
    collectionViewConfiguration(self)

    collectionDataSource.supplementaryViewProvider = supplementaryViewProvider
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func apply(_ snapshot: Snapshot,
             animatingDifferences: Bool = true,
             completion: (() -> Void)? = nil)
  {
    updateQueue.async { [weak self] in
      self?.collectionDataSource.apply(
        snapshot,
        animatingDifferences: animatingDifferences,
        completion: completion,
      )
    }
  }
}
