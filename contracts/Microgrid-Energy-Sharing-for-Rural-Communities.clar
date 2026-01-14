(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INVALID_AMOUNT (err u101))
(define-constant ERR_INSUFFICIENT_BALANCE (err u102))
(define-constant ERR_LISTING_NOT_FOUND (err u103))
(define-constant ERR_INVALID_USER (err u104))
(define-constant ERR_ALREADY_REGISTERED (err u105))
(define-constant ERR_TRADE_NOT_FOUND (err u106))
(define-constant ERR_CANNOT_BUY_OWN_ENERGY (err u107))
(define-constant ERR_INSUFFICIENT_ENERGY (err u108))
(define-constant ERR_INVALID_PRICE_MULTIPLIER (err u109))

(define-constant REFERRAL_REWARD u10)

(define-data-var contract-active bool true)
(define-data-var base-energy-price uint u50)
(define-data-var total-energy-supply uint u0)
(define-data-var total-energy-demand uint u0)
(define-data-var price-update-threshold uint u100)
(define-data-var last-price-update uint u0)
(define-data-var total-energy-traded uint u0)
(define-data-var total-users uint u0)
(define-data-var listing-nonce uint u0)
(define-data-var trade-nonce uint u0)
(define-data-var auction-nonce uint u0)

(define-data-var community-emergency-fund uint u0)

(define-map users
  principal
  {
    balance: uint,
    energy-produced: uint,
    energy-consumed: uint,
    reputation-score: uint,
    is-producer: bool,
    location: (string-ascii 50),
    registered-at: uint,
    has-traded: bool,
    referrer: (optional principal)
  }
)

(define-map energy-listings
  uint
  {
    seller: principal,
    amount: uint,
    price-per-kwh: uint,
    available: bool,
    location: (string-ascii 50),
    renewable-type: (string-ascii 20),
    created-at: uint
  }
)

(define-map trades
  uint
  {
    buyer: principal,
    seller: principal,
    listing-id: uint,
    amount: uint,
    total-price: uint,
    settled: bool,
    trade-time: uint
  }
)

(define-map smart-meter-readings
  {user: principal, timestamp: uint}
  {
    energy-produced: uint,
    energy-consumed: uint,
    grid-contribution: uint
  }
)

(define-map auctions
  uint
  {
    listing-id: uint,
    seller: principal,
    min-price: uint,
    end-time: uint,
    highest-bid: uint,
    highest-bidder: (optional principal),
    active: bool
  }
)

(define-map bids
  {auction-id: uint, bidder: principal}
  uint
)

(define-read-only (get-user-info (user principal))
  (map-get? users user)
)

(define-read-only (get-energy-listing (listing-id uint))
  (map-get? energy-listings listing-id)
)

(define-read-only (get-trade-info (trade-id uint))
  (map-get? trades trade-id)
)

(define-read-only (get-contract-stats)
  {
    total-energy-traded: (var-get total-energy-traded),
    total-users: (var-get total-users),
    contract-active: (var-get contract-active)
  }
)

(define-read-only (get-meter-reading (user principal) (timestamp uint))
  (map-get? smart-meter-readings {user: user, timestamp: timestamp})
)

(define-read-only (get-auction-info (auction-id uint))
  (map-get? auctions auction-id)
)

(define-read-only (calculate-energy-cost (amount uint) (price-per-kwh uint))
  (* amount price-per-kwh)
)

(define-public (register-user (location (string-ascii 50)) (is-producer bool) (referrer (optional principal)))
  (let ((user tx-sender))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? users user)) ERR_ALREADY_REGISTERED)
    (map-set users user
      {
        balance: u0,
        energy-produced: u0,
        energy-consumed: u0,
        reputation-score: u100,
        is-producer: is-producer,
        location: location,
        registered-at: stacks-block-height,
        has-traded: false,
        referrer: referrer
      }
    )
    (var-set total-users (+ (var-get total-users) u1))
    (ok true)
  )
)

(define-public (deposit-funds (amount uint))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (try! (stx-transfer? amount user (as-contract tx-sender)))
    (map-set users user
      (merge user-data {balance: (+ (get balance user-data) amount)})
    )
    (ok amount)
  )
)

(define-public (withdraw-funds (amount uint))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get balance user-data) amount) ERR_INSUFFICIENT_BALANCE)
    (try! (as-contract (stx-transfer? amount tx-sender user)))
    (map-set users user
      (merge user-data {balance: (- (get balance user-data) amount)})
    )
    (ok amount)
  )
)

(define-public (list-energy (amount uint) (price-per-kwh uint) (renewable-type (string-ascii 20)))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER))
        (listing-id (+ (var-get listing-nonce) u1)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get is-producer user-data) ERR_NOT_AUTHORIZED)
    (asserts! (and (> amount u0) (> price-per-kwh u0)) ERR_INVALID_AMOUNT)
    (map-set energy-listings listing-id
      {
        seller: user,
        amount: amount,
        price-per-kwh: price-per-kwh,
        available: true,
        location: (get location user-data),
        renewable-type: renewable-type,
        created-at: stacks-block-height
      }
    )
    (var-set listing-nonce listing-id)
    (var-set total-energy-supply (+ (var-get total-energy-supply) amount))
    (let ((price-result (update-market-price)))
      (ok listing-id))
  )
)

(define-public (buy-energy (listing-id uint) (amount uint))
  (let ((buyer tx-sender)
        (buyer-data (unwrap! (map-get? users buyer) ERR_INVALID_USER))
        (listing (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND))
        (seller (get seller listing))
        (seller-data (unwrap! (map-get? users seller) ERR_INVALID_USER))
        (total-cost (calculate-energy-cost amount (get price-per-kwh listing)))
        (trade-id (+ (var-get trade-nonce) u1))
        (is-first-trade (not (get has-traded buyer-data))))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get available listing) ERR_LISTING_NOT_FOUND)
    (asserts! (not (is-eq buyer seller)) ERR_CANNOT_BUY_OWN_ENERGY)
    (asserts! (>= (get amount listing) amount) ERR_INSUFFICIENT_ENERGY)
    (asserts! (>= (get balance buyer-data) total-cost) ERR_INSUFFICIENT_BALANCE)
    (map-set users buyer
      (merge buyer-data
        (if is-first-trade
          {
            balance: (- (get balance buyer-data) total-cost),
            energy-consumed: (+ (get energy-consumed buyer-data) amount),
            has-traded: true
          }
          {
            balance: (- (get balance buyer-data) total-cost),
            energy-consumed: (+ (get energy-consumed buyer-data) amount),
            has-traded: true
          }
        )
      )
    )
    (map-set users seller
      (merge seller-data 
        {
          balance: (+ (get balance seller-data) total-cost),
          energy-produced: (+ (get energy-produced seller-data) amount),
          reputation-score: (+ (get reputation-score seller-data) u1)
        }
      )
    )
    (if (is-eq (get amount listing) amount)
      (map-set energy-listings listing-id (merge listing {available: false}))
      (map-set energy-listings listing-id (merge listing {amount: (- (get amount listing) amount)}))
    )
    (map-set trades trade-id
      {
        buyer: buyer,
        seller: seller,
        listing-id: listing-id,
        amount: amount,
        total-price: total-cost,
        settled: true,
        trade-time: stacks-block-height
      }
    )
    (var-set trade-nonce trade-id)
    (var-set total-energy-traded (+ (var-get total-energy-traded) amount))
    (var-set total-energy-demand (+ (var-get total-energy-demand) amount))
    (var-set total-energy-supply (if (>= (var-get total-energy-supply) amount)
      (- (var-get total-energy-supply) amount)
      u0))
    (if is-first-trade
      (match (get referrer buyer-data)
        some-referrer (match (map-get? users some-referrer)
                      some-data (begin
                                  (try! (as-contract (stx-transfer? REFERRAL_REWARD tx-sender some-referrer)))
                                  (map-set users some-referrer (merge some-data {balance: (+ (get balance some-data) REFERRAL_REWARD)}))
                                  true)
                      false)
        true)
      true)
    (let ((price-result (update-market-price)))
      (ok trade-id))
  )
)

(define-public (record-meter-reading (energy-produced uint) (energy-consumed uint) (grid-contribution uint))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER))
        (timestamp stacks-block-height))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (map-set smart-meter-readings 
      {user: user, timestamp: timestamp}
      {
        energy-produced: energy-produced,
        energy-consumed: energy-consumed,
        grid-contribution: grid-contribution
      }
    )
    (map-set users user
      (merge user-data 
        {
          energy-produced: (+ (get energy-produced user-data) energy-produced),
          energy-consumed: (+ (get energy-consumed user-data) energy-consumed)
        }
      )
    )
    (ok timestamp)
  )
)

(define-public (update-listing-price (listing-id uint) (new-price uint))
  (let ((user tx-sender)
        (listing (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq user (get seller listing)) ERR_NOT_AUTHORIZED)
    (asserts! (get available listing) ERR_LISTING_NOT_FOUND)
    (asserts! (> new-price u0) ERR_INVALID_AMOUNT)
    (map-set energy-listings listing-id
      (merge listing {price-per-kwh: new-price})
    )
    (ok true)
  )
)

(define-public (cancel-listing (listing-id uint))
  (let ((user tx-sender)
        (listing (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq user (get seller listing)) ERR_NOT_AUTHORIZED)
    (asserts! (get available listing) ERR_LISTING_NOT_FOUND)
    (map-set energy-listings listing-id
      (merge listing {available: false})
    )
    (ok true)
  )
)

(define-public (update-reputation (user principal) (score-change int))
  (let ((user-data (unwrap! (map-get? users user) ERR_INVALID_USER))
        (current-score (get reputation-score user-data)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (map-set users user
      (merge user-data 
        {
          reputation-score: (if (> score-change 0)
            (+ current-score (to-uint score-change))
            (if (>= current-score (to-uint (- score-change)))
              (- current-score (to-uint (- score-change)))
              u0
            )
          )
        }
      )
    )
    (ok true)
  )
)

(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-active false)
    (ok true)
  )
)

(define-public (resume-contract)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set contract-active true)
    (ok true)
  )
)

(define-read-only (get-available-listings)
  (ok (list
    (var-get listing-nonce)
  ))
)

(define-read-only (calculate-grid-fees (amount uint))
  (/ (* amount u5) u100)
)

(define-read-only (get-user-balance (user principal))
  (match (map-get? users user)
    user-data (ok (get balance user-data))
    ERR_INVALID_USER
  )
)

(define-read-only (get-user-energy-stats (user principal))
  (match (map-get? users user)
    user-data (ok {
      energy-produced: (get energy-produced user-data),
      energy-consumed: (get energy-consumed user-data),
      reputation-score: (get reputation-score user-data)
    })
    ERR_INVALID_USER
  )
)

(define-public (batch-settle-trades (trade-ids (list 10 uint)))
  (let ((user tx-sender))
    (asserts! (is-eq user CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (ok (map settle-single-trade trade-ids))
  )
)

(define-private (settle-single-trade (trade-id uint))
  (match (map-get? trades trade-id)
    trade-data (if (get settled trade-data)
      trade-id
      (begin
        (map-set trades trade-id (merge trade-data {settled: true}))
        trade-id
      )
    )
    trade-id
  )
)

(define-read-only (get-user-trading-history (user principal))
  (ok (var-get trade-nonce))
)

(define-public (update-user-location (new-location (string-ascii 50)))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (map-set users user
      (merge user-data {location: new-location})
    )
    (ok true)
  )
)

(define-read-only (estimate-trade-cost (listing-id uint) (amount uint))
  (match (map-get? energy-listings listing-id)
    listing (let ((base-cost (calculate-energy-cost amount (get price-per-kwh listing)))
                  (grid-fee (calculate-grid-fees base-cost)))
              (ok (+ base-cost grid-fee)))
    ERR_LISTING_NOT_FOUND
  )
)

(define-public (reward-renewable-producer (user principal) (bonus-amount uint))
  (let ((user-data (unwrap! (map-get? users user) ERR_INVALID_USER)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get is-producer user-data) ERR_NOT_AUTHORIZED)
    (try! (as-contract (stx-transfer? bonus-amount tx-sender user)))
    (map-set users user
      (merge user-data 
        {
          balance: (+ (get balance user-data) bonus-amount),
          reputation-score: (+ (get reputation-score user-data) u5)
        }
      )
    )
    (ok bonus-amount)
  )
)

(define-read-only (get-current-market-price)
  (var-get base-energy-price)
)

(define-read-only (get-market-stats)
  {
    base-price: (var-get base-energy-price),
    total-supply: (var-get total-energy-supply),
    total-demand: (var-get total-energy-demand),
    current-price: (calculate-dynamic-price),
    last-update: (var-get last-price-update)
  }
)

(define-read-only (calculate-dynamic-price)
  (let ((supply (var-get total-energy-supply))
        (demand (var-get total-energy-demand))
        (base-price (var-get base-energy-price)))
    (if (is-eq supply u0)
      (* base-price u2)
      (let ((demand-ratio (/ (* demand u100) supply)))
        (if (> demand-ratio u150)
          (* base-price u2)
          (if (> demand-ratio u120)
            (+ base-price (/ base-price u2))
            (if (< demand-ratio u80)
              (- base-price (/ base-price u4))
              base-price
            )
          )
        )
      )
    )
  )
)

(define-read-only (calculate-supply-demand-ratio)
  (let ((supply (var-get total-energy-supply))
        (demand (var-get total-energy-demand)))
    (if (is-eq supply u0)
      u200
      (/ (* demand u100) supply)
    )
  )
)

(define-public (update-market-price)
  (let ((current-height stacks-block-height)
        (last-update (var-get last-price-update))
        (threshold (var-get price-update-threshold))
        (new-price (calculate-dynamic-price)))
    (if (>= (- current-height last-update) threshold)
      (begin
        (var-set base-energy-price new-price)
        (var-set last-price-update current-height)
        (ok new-price)
      )
      (ok (var-get base-energy-price))
    )
  )
)

(define-public (set-price-update-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (> new-threshold u0) ERR_INVALID_AMOUNT)
    (var-set price-update-threshold new-threshold)
    (ok new-threshold)
  )
)

(define-public (manual-price-adjustment (multiplier uint))
  (let ((current-price (var-get base-energy-price)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= multiplier u50) (<= multiplier u200)) ERR_INVALID_PRICE_MULTIPLIER)
    (var-set base-energy-price (/ (* current-price multiplier) u100))
    (var-set last-price-update stacks-block-height)
    (ok (var-get base-energy-price))
  )
)

(define-public (reset-supply-demand-counters)
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set total-energy-supply u0)
    (var-set total-energy-demand u0)
    (ok true)
  )
)

(define-read-only (get-price-recommendation (amount uint) (listing-type (string-ascii 10)))
  (let ((market-price (calculate-dynamic-price))
        (supply-ratio (calculate-supply-demand-ratio)))
    (if (is-eq listing-type "urgent")
      (* market-price u1)
      (if (< supply-ratio u80)
        (- market-price (/ market-price u10))
        (if (> supply-ratio u120)
          (+ market-price (/ market-price u10))
          market-price
        )
      )
    )
  )
)

(define-read-only (estimate-optimal-listing-time)
  (let ((supply-ratio (calculate-supply-demand-ratio)))
    (if (> supply-ratio u150)
      {
        recommended-action: "wait",
        reason: "high-demand-period",
        price-multiplier: u150
      }
      {
        recommended-action: "list-now",
        reason: "favorable-conditions",
        price-multiplier: u100
      }
    )
  )
)

(define-read-only (get-emergency-fund-balance)
  (var-get community-emergency-fund)
)

(define-public (contribute-to-emergency-fund (amount uint))
  (let ((user tx-sender)
        (user-data (unwrap! (map-get? users user) ERR_INVALID_USER)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (>= (get balance user-data) amount) ERR_INSUFFICIENT_BALANCE)
    (try! (stx-transfer? amount user (as-contract tx-sender)))
    (map-set users user
      (merge user-data {balance: (- (get balance user-data) amount)})
    )
    (var-set community-emergency-fund (+ (var-get community-emergency-fund) amount))
    (ok amount)
  )
)

(define-public (distribute-emergency-fund (recipients (list 10 principal)) (amounts (list 10 uint)))
  (let ((total-distribution (fold + amounts u0)))
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (>= (var-get community-emergency-fund) total-distribution) ERR_INSUFFICIENT_BALANCE)
    (var-set community-emergency-fund (- (var-get community-emergency-fund) total-distribution))
    (ok (map distribute-to-recipient recipients amounts))
  )
)

(define-private (distribute-to-recipient (recipient principal) (amount uint))
  (let ((recipient-data (unwrap! (map-get? users recipient) ERR_INVALID_USER)))
    (try! (as-contract (stx-transfer? amount tx-sender recipient)))
    (map-set users recipient
      (merge recipient-data {balance: (+ (get balance recipient-data) amount)})
    )
    (ok amount)
  )
)

(define-public (start-auction (listing-id uint) (min-price uint) (duration uint))
  (let ((user tx-sender)
        (listing (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND))
        (auction-id (+ (var-get auction-nonce) u1)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq user (get seller listing)) ERR_NOT_AUTHORIZED)
    (asserts! (get available listing) ERR_LISTING_NOT_FOUND)
    (asserts! (> min-price u0) ERR_INVALID_AMOUNT)
    (asserts! (> duration u0) ERR_INVALID_AMOUNT)
    (map-set energy-listings listing-id (merge listing {available: false}))
    (map-set auctions auction-id
      {
        listing-id: listing-id,
        seller: user,
        min-price: min-price,
        end-time: (+ stacks-block-height duration),
        highest-bid: u0,
        highest-bidder: none,
        active: true
      }
    )
    (var-set auction-nonce auction-id)
    (ok auction-id)
  )
)

(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let ((bidder tx-sender)
        (auction (unwrap! (map-get? auctions auction-id) ERR_LISTING_NOT_FOUND))
        (bidder-data (unwrap! (map-get? users bidder) ERR_INVALID_USER))
        (current-highest (get highest-bid auction)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get active auction) ERR_LISTING_NOT_FOUND)
    (asserts! (< stacks-block-height (get end-time auction)) ERR_INVALID_AMOUNT)
    (asserts! (> bid-amount (get min-price auction)) ERR_INVALID_AMOUNT)
    (asserts! (> bid-amount current-highest) ERR_INVALID_AMOUNT)
    (asserts! (>= (get balance bidder-data) bid-amount) ERR_INSUFFICIENT_BALANCE)
    (if (is-some (get highest-bidder auction))
      (let ((prev-bidder (unwrap-panic (get highest-bidder auction)))
            (prev-bid (unwrap-panic (map-get? bids {auction-id: auction-id, bidder: prev-bidder}))))
        (try! (as-contract (stx-transfer? prev-bid tx-sender prev-bidder)))
        (map-set users prev-bidder (merge (unwrap! (map-get? users prev-bidder) ERR_INVALID_USER) {balance: (+ (get balance (unwrap! (map-get? users prev-bidder) ERR_INVALID_USER)) prev-bid)}))
      )
      true
    )
    (try! (stx-transfer? bid-amount bidder (as-contract tx-sender)))
    (map-set users bidder (merge bidder-data {balance: (- (get balance bidder-data) bid-amount)}))
    (map-set bids {auction-id: auction-id, bidder: bidder} bid-amount)
    (map-set auctions auction-id (merge auction {highest-bid: bid-amount, highest-bidder: (some bidder)}))
    (ok bid-amount)
  )
)

(define-public (end-auction (auction-id uint))
  (let ((auction (unwrap! (map-get? auctions auction-id) ERR_LISTING_NOT_FOUND))
        (seller (get seller auction))
        (listing-id (get listing-id auction)))
    (asserts! (var-get contract-active) ERR_NOT_AUTHORIZED)
    (asserts! (get active auction) ERR_LISTING_NOT_FOUND)
    (asserts! (>= stacks-block-height (get end-time auction)) ERR_INVALID_AMOUNT)
    (map-set auctions auction-id (merge auction {active: false}))
    (if (is-some (get highest-bidder auction))
      (let ((winner (unwrap-panic (get highest-bidder auction)))
            (final-bid (get highest-bid auction))
            (listing (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND))
            (amount (get amount listing))
            (trade-id (+ (var-get trade-nonce) u1))
            (seller-data (unwrap! (map-get? users seller) ERR_INVALID_USER))
            (winner-data (unwrap! (map-get? users winner) ERR_INVALID_USER)))
        (try! (as-contract (stx-transfer? final-bid tx-sender seller)))
        (map-set users seller (merge seller-data {balance: (+ (get balance seller-data) final-bid), energy-produced: (+ (get energy-produced seller-data) amount), reputation-score: (+ (get reputation-score seller-data) u1)}))
        (map-set users winner (merge winner-data {energy-consumed: (+ (get energy-consumed winner-data) amount), has-traded: true}))
        (map-set trades trade-id
          {
            buyer: winner,
            seller: seller,
            listing-id: listing-id,
            amount: amount,
            total-price: final-bid,
            settled: true,
            trade-time: stacks-block-height
          }
        )
        (var-set trade-nonce trade-id)
        (var-set total-energy-traded (+ (var-get total-energy-traded) amount))
        (var-set total-energy-demand (+ (var-get total-energy-demand) amount))
        (var-set total-energy-supply (if (>= (var-get total-energy-supply) amount) (- (var-get total-energy-supply) amount) u0))
        (ok trade-id)
      )
      (begin
        (map-set energy-listings listing-id (merge (unwrap! (map-get? energy-listings listing-id) ERR_LISTING_NOT_FOUND) {available: true}))
        (ok u0)
      )
    )
  )
)
