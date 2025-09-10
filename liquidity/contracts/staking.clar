;; Liquidity Staking Contract
;; Implements liquidity provision and staking mechanics with custom min function

;; Define fungible token trait
(define-trait ft-trait
    (
        (transfer (uint principal principal) (response bool uint))
        (get-name () (response (string-ascii 32) uint))
        (get-symbol () (response (string-ascii 32) uint))
        (get-decimals () (response uint uint))
        (get-balance (principal) (response uint uint))
        (get-total-supply () (response uint uint))
    )
)

;; Define token contracts
(define-constant token-a-principal .token-a)
(define-constant token-b-principal .token-b)

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u1))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u2))
(define-constant ERR-ALREADY-PROVIDED (err u3))
(define-constant ERR-NO-LIQUIDITY (err u4))
(define-constant ERR-MINIMUM-AMOUNT (err u5))
(define-constant ERR-LOCKED-PERIOD (err u6))
(define-constant ERR-INVALID-PAIR (err u7))
(define-constant ERR-CALCULATION-ERROR (err u8))
(define-constant ERR-INVALID-OWNER (err u9))
(define-constant ERR-OWNER-VALIDATION (err u10))

;; Constants
(define-constant MINIMUM-LIQUIDITY u100000) ;; Minimum liquidity requirement
(define-constant LOCK_PERIOD u144) ;; ~24 hours in blocks
(define-constant REWARD_MULTIPLIER u100) ;; 1.00x base multiplier
(define-constant FEE_PERCENTAGE u30) ;; 0.3% fee
(define-constant ZERO_ADDRESS 'SP000000000000000000002Q6VF78)

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-liquidity uint u0)
(define-data-var last-update-block uint u0)
(define-data-var pool-active bool true)
(define-data-var reward-multiplier uint REWARD_MULTIPLIER)

;; Data maps for liquidity providers
(define-map liquidity-providers
    principal
    {
        token-a: uint,
        token-b: uint,
        liquidity-tokens: uint,
        start-block: uint,
        last-reward-claim: uint,
        locked-until: uint
    }
)

;; Pool data structure
(define-map pools
    uint
    {
        token-a-balance: uint,
        token-b-balance: uint,
        total-shares: uint,
        fee-accumulated: uint
    }
)

;; Custom minimum function implementation
(define-private (get-minimum (a uint) (b uint))
    (if (<= a b)
        a
        b))

;; Read-only functions
(define-read-only (get-provider-info (provider principal))
    (map-get? liquidity-providers provider)
)

(define-read-only (get-pool-info (pool-id uint))
    (map-get? pools pool-id)
)

(define-read-only (calculate-liquidity-share (amount-a uint) (amount-b uint))
    (let (
        (pool (unwrap! (get-pool-info u1) (err ERR-CALCULATION-ERROR)))
        (total-shares (get total-shares pool))
    )
    (ok (if (is-eq total-shares u0)
        (sqrti (* amount-a amount-b))
        (get-minimum
            (/ (* amount-a total-shares) (get token-a-balance pool))
            (/ (* amount-b total-shares) (get token-b-balance pool))
        )))
    )
)

;; Public functions
(define-public (add-liquidity (token-a <ft-trait>) (token-b <ft-trait>) (token-a-amount uint) (token-b-amount uint))
    (begin
        (asserts! (and 
            (is-eq (contract-of token-a) token-a-principal)
            (is-eq (contract-of token-b) token-b-principal))
            ERR-INVALID-PAIR)
            
        (let (
            (provider-info (default-to 
                {
                    token-a: u0,
                    token-b: u0,
                    liquidity-tokens: u0,
                    start-block: u0,
                    last-reward-claim: block-height,
                    locked-until: u0
                }
                (map-get? liquidity-providers tx-sender)))
            (shares-response (calculate-liquidity-share token-a-amount token-b-amount))
        )
        (asserts! (>= token-a-amount MINIMUM-LIQUIDITY) ERR-MINIMUM-AMOUNT)
        (asserts! (>= token-b-amount MINIMUM-LIQUIDITY) ERR-MINIMUM-AMOUNT)
        (asserts! (is-eq (get liquidity-tokens provider-info) u0) ERR-ALREADY-PROVIDED)
        
        (let 
            ((shares (unwrap! shares-response ERR-CALCULATION-ERROR)))
            
            ;; Transfer tokens to contract
            (try! (contract-call? token-a transfer token-a-amount tx-sender (as-contract tx-sender)))
            (try! (contract-call? token-b transfer token-b-amount tx-sender (as-contract tx-sender)))
            
            ;; Update provider info
            (map-set liquidity-providers tx-sender
                {
                    token-a: token-a-amount,
                    token-b: token-b-amount,
                    liquidity-tokens: shares,
                    start-block: block-height,
                    last-reward-claim: block-height,
                    locked-until: (+ block-height LOCK_PERIOD)
                }
            )
            
            ;; Update pool info
            (try! (update-pool-balances token-a-amount token-b-amount shares))
            (ok shares)))
    )
)

(define-public (remove-liquidity (token-a <ft-trait>) (token-b <ft-trait>))
    (begin
        (asserts! (and 
            (is-eq (contract-of token-a) token-a-principal)
            (is-eq (contract-of token-b) token-b-principal))
            ERR-INVALID-PAIR)
            
        (let (
            (provider-info (unwrap! (get-provider-info tx-sender) ERR-NO-LIQUIDITY))
            (current-block block-height)
        )
        (asserts! (>= current-block (get locked-until provider-info)) ERR-LOCKED-PERIOD)
        
        (let (
            (token-a-amount (get token-a provider-info))
            (token-b-amount (get token-b provider-info))
            (shares (get liquidity-tokens provider-info))
        )
            ;; Calculate rewards
            (let (
                (rewards (calculate-rewards tx-sender))
                (total-a (+ token-a-amount rewards))
                (total-b (+ token-b-amount rewards))
            )
                ;; Transfer tokens back to provider
                (try! (as-contract (contract-call? token-a transfer total-a (as-contract tx-sender) tx-sender)))
                (try! (as-contract (contract-call? token-b transfer total-b (as-contract tx-sender) tx-sender)))
                
                ;; Update state
                (map-delete liquidity-providers tx-sender)
                (try! (update-pool-balances total-a total-b shares))
                (ok true)
            ))))
)

;; Private helper functions
(define-private (update-pool-balances (delta-a uint) (delta-b uint) (delta-shares uint))
    (let (
        (pool (unwrap! (get-pool-info u1) ERR-CALCULATION-ERROR))
        (new-token-a-balance (- (get token-a-balance pool) delta-a))
        (new-token-b-balance (- (get token-b-balance pool) delta-b))
        (new-total-shares (- (get total-shares pool) delta-shares))
    )
    (asserts! (and (>= new-token-a-balance u0) (>= new-token-b-balance u0) (>= new-total-shares u0)) ERR-INSUFFICIENT-LIQUIDITY)
    (map-set pools u1
        {
            token-a-balance: new-token-a-balance,
            token-b-balance: new-token-b-balance,
            total-shares: new-total-shares,
            fee-accumulated: (get fee-accumulated pool)
        }
    )
    (ok true))
)

(define-private (calculate-rewards (provider principal))
    (let (
        (provider-info (unwrap! (get-provider-info provider) u0))
        (blocks-staked (- block-height (get last-reward-claim provider-info)))
        (share (get liquidity-tokens provider-info))
    )
    (/ (* (* share blocks-staked) (var-get reward-multiplier)) u10000))
)

;; Administrative functions
(define-private (validate-and-set-owner (new-owner principal))
    (begin
        (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR-INVALID-OWNER)
        (let ((provider-info (get-provider-info new-owner)))
            (asserts! (is-some provider-info) ERR-INVALID-OWNER)
            (let ((unwrapped-info (unwrap! provider-info ERR-OWNER-VALIDATION)))
                (asserts! (> (get liquidity-tokens unwrapped-info) u0) ERR-OWNER-VALIDATION)
                (asserts! (>= block-height (get locked-until unwrapped-info)) ERR-OWNER-VALIDATION)
                (ok (var-set contract-owner new-owner)))))
)

(define-public (set-owner (new-owner principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (not (is-eq new-owner ZERO_ADDRESS)) ERR-INVALID-OWNER)
        (try! (validate-and-set-owner new-owner))
        (ok true))
)

(define-public (update-reward-multiplier (new-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (> new-multiplier u0) ERR-INVALID-PAIR)
        (ok (var-set reward-multiplier new-multiplier)))
)

(define-public (toggle-pool-status)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set pool-active (not (var-get pool-active)))
        (ok true))
)

