//
//  SubredditLinkListViewModel.swift
//  Reddit
//
//  Created by Ivan Bruel on 09/05/16.
//  Copyright © 2016 Faber Ventures. All rights reserved.
//

import Foundation
import RxSwift

// MARK: Properties and initializer
class LinkListViewModel {

  // MARK: Private Properties
  private let _title: String
  private let path: String
  private let user: User?
  private let accessToken: AccessToken?
  private let linkListings: Variable<[LinkListing]> = Variable([])
  private let _viewModels: Variable<[LinkItemViewModel]> = Variable([])
  private let _listingType: Variable<ListingType> = Variable(.Hot)
  private var disposeBag = DisposeBag()
  private let _loadingState = Variable<LoadingState>(.Normal)

  // MARK: Initializer
  init(user: User?, accessToken: AccessToken?, title: String, path: String) {
    self.user = user
    self.accessToken = accessToken
    self._title = title
    self.path = path
  }

  convenience init(user: User?, accessToken: AccessToken?, subreddit: Subreddit) {
    self.init(user: user, accessToken: accessToken, title: subreddit.displayName,
              path: subreddit.path)
  }

  convenience init(user: User?, accessToken: AccessToken?, multireddit: Multireddit) {
    self.init(user: user, accessToken: accessToken, title: multireddit.name,
              path: multireddit.path)
  }
}

// MARK: Private Observables
extension LinkListViewModel {

  private var userObservable: Observable<User?> {
    return .just(user)
  }

  private var accessTokenObservable: Observable<AccessToken?> {
    return .just(accessToken)
  }

  private var afterObservable: Observable<String?> {
    return linkListings.asObservable()
      .map { $0.last?.after }
  }

  private var listingTypeObservable: Observable<ListingType> {
    return _listingType.asObservable()
  }

  private var pathObservable: Observable<String> {
    return .just(path)
  }

  private var linksObservable: Observable<[Link]> {
    return linkListings.asObservable()
      .map { (linkListings: [LinkListing]) -> [Link] in
        Array(linkListings.flatMap { $0.links }.flatten())
    }
  }

  private var request: Observable<LinkListing> {
    return Observable
      .combineLatest(listingTypeObservable, afterObservable, accessTokenObservable,
        pathObservable) { ($0, $1, $2, $3) }
      .take(1)
      .doOnNext { [weak self] _ in
        self?._loadingState.value = .Loading
      }.flatMap {
        (listingType: ListingType, after: String?, accessToken: AccessToken?, path: String) in
        Network.request(RedditAPI.LinkListing(token: accessToken?.token,
          path: path, listingPath: listingType.path, listingTypeRange: listingType.range?.rawValue,
          after: after))
      }.observeOn(SerialDispatchQueueScheduler(globalConcurrentQueueQOS: .Background))
      .mapObject(LinkListing)
      .observeOn(MainScheduler.instance)
  }
}

// MARK: Public API
extension LinkListViewModel {

  var viewModels: Observable<[LinkItemViewModel]> {
    return _viewModels.asObservable()
  }

  var loadingState: Observable<LoadingState> {
    return _loadingState.asObservable()
  }

  var listingTypeName: Observable<String> {
    return _listingType.asObservable()
      .map { $0.name }
  }

  func viewModelForIndex(index: Int) -> LinkItemViewModel? {
    return _viewModels.value.get(index)
  }

  func requestLinks() {
    guard _loadingState.value != .Loading else { return }

    Observable.combineLatest(request, userObservable, accessTokenObservable) { ($0, $1, $2) }
      .take(1)
      .subscribe { [weak self] event in
        guard let `self` = self else { return }

        switch event {
        case let .Next(linkListing, user, accessToken):
          self.linkListings.value.append(linkListing)
          let viewModels = LinkListViewModel.viewModelsFromLinkListing(linkListing,
            user: user, accessToken: accessToken)
          viewModels.forEach { $0.preloadData() }
          self._viewModels.value += viewModels
          self._loadingState.value = self._viewModels.value.count > 0 ? .Normal : .Empty
        case .Error:
          self._loadingState.value = .Error
        default: break
        }

      }.addDisposableTo(disposeBag)
  }

  func setListingType(listingType: ListingType) {
    guard listingType != _listingType.value else { return }
    _listingType.value = listingType
    refresh()
  }

  func refresh() {
    linkListings.value = []
    _viewModels.value = []
    disposeBag = DisposeBag()
    _loadingState.value = .Normal
    requestLinks()
  }
}

// MARK: Helpers
extension LinkListViewModel {


  private static func viewModelsFromLinkListing(linkListing: LinkListing, user: User?,
                                                accessToken: AccessToken?)
    -> [LinkItemViewModel] {
      return linkListing.links.map { links in
        LinkItemViewModel.viewModelFromLink(links, user: user, accessToken: accessToken)
      }
  }
}

// MARK: TitledViewModel
extension LinkListViewModel: TitledViewModel {

  var title: Observable<String> {
    return .just(_title)
  }
}
