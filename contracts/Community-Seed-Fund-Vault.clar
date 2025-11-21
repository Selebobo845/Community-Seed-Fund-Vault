(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_FUNDS (err u101))
(define-constant ERR_LOAN_NOT_FOUND (err u102))
(define-constant ERR_LOAN_ALREADY_REPAID (err u103))
(define-constant ERR_INVALID_AMOUNT (err u104))
(define-constant ERR_LOAN_OVERDUE (err u105))
(define-constant ERR_FARMER_NOT_REGISTERED (err u106))
(define-constant ERR_FARMER_ALREADY_REGISTERED (err u107))
(define-constant ERR_LOAN_NOT_APPROVED (err u108))
(define-constant ERR_LOAN_ALREADY_APPROVED (err u109))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u110))
(define-constant ERR_COLLATERAL_NOT_FOUND (err u111))
(define-constant ERR_COLLATERAL_ALREADY_DEPOSITED (err u112))
(define-constant ERR_INVALID_REPUTATION_TIER (err u113))
(define-constant ERR_ALERT_NOT_FOUND (err u114))
(define-constant ERR_INVALID_ALERT_THRESHOLD (err u115))
(define-constant ERR_FUND_BALANCE_TOO_LOW (err u116))
(define-constant ERR_CONTRACT_PAUSED (err u117))

(define-data-var total-fund-balance uint u0)
(define-data-var next-loan-id uint u1)
(define-data-var interest-rate uint u10)
(define-data-var loan-duration-blocks uint u4320)
(define-data-var collateral-ratio uint u150)
(define-data-var base-interest-rate uint u15)
(define-data-var reputation-discount-rate uint u5)
(define-data-var contract-pause-state {
    paused: bool,
    reason: (string-ascii 100),
    since-block: uint,
} {
    paused: false,
    reason: "",
    since-block: u0,
})

;; === LOAN ALERT SYSTEM DATA STRUCTURES ===

;; Alert settings with configurable thresholds
(define-data-var alert-settings {
    seven-day-threshold: uint,
    three-day-threshold: uint,
    one-day-threshold: uint,
    fund-low-balance-threshold: uint,
    enabled: bool,
} {
    seven-day-threshold: u1008, ;; 7 days in blocks (~144 blocks/day)
    three-day-threshold: u432, ;; 3 days in blocks
    one-day-threshold: u144, ;; 1 day in blocks
    fund-low-balance-threshold: u100000000, ;; 1000 STX minimum
    enabled: true,
})

;; Fund health metrics for performance monitoring
(define-data-var fund-health-metrics {
    total-active-loans: uint,
    total-overdue-loans: uint,
    utilization-rate: uint,
    default-rate: uint,
    last-updated: uint,
} {
    total-active-loans: u0,
    total-overdue-loans: u0,
    utilization-rate: u0,
    default-rate: u0,
    last-updated: u0,
})

(define-map farmers
    principal
    {
        name: (string-ascii 50),
        location: (string-ascii 100),
        registered-at: uint,
        total-borrowed: uint,
        total-repaid: uint,
        active-loans: uint,
        reputation-score: uint,
        successful-loans: uint,
        total-loans: uint,
    }
)

(define-map loans
    uint
    {
        farmer: principal,
        amount: uint,
        interest: uint,
        requested-at: uint,
        approved-at: (optional uint),
        due-at: (optional uint),
        repaid-at: (optional uint),
        approved: bool,
        repaid: bool,
    }
)

(define-map contributors
    principal
    {
        total-contributed: uint,
        contribution-count: uint,
    }
)

(define-map collateral-deposits
    principal
    {
        amount: uint,
        deposited-at: uint,
        locked: bool,
        linked-loan: (optional uint),
    }
)

;; Loan alert tracking map for milestone notifications
(define-map loan-alerts
    { loan-id: uint }
    {
        seven-day-alert: bool,
        three-day-alert: bool,
        one-day-alert: bool,
        overdue-alert: bool,
        last-check: uint,
    }
)

(define-public (register-farmer
        (name (string-ascii 50))
        (location (string-ascii 100))
    )
    (let ((farmer tx-sender))
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-none (map-get? farmers farmer))
            ERR_FARMER_ALREADY_REGISTERED
        )
        (map-set farmers farmer {
            name: name,
            location: location,
            registered-at: stacks-block-height,
            total-borrowed: u0,
            total-repaid: u0,
            active-loans: u0,
            reputation-score: u100,
            successful-loans: u0,
            total-loans: u0,
        })
        (ok true)
    )
)

(define-public (contribute-to-fund (amount uint))
    (let ((contributor tx-sender))
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (try! (stx-transfer? amount contributor (as-contract tx-sender)))
        (var-set total-fund-balance (+ (var-get total-fund-balance) amount))
        (match (map-get? contributors contributor)
            existing-contributor (map-set contributors contributor {
                total-contributed: (+ (get total-contributed existing-contributor) amount),
                contribution-count: (+ (get contribution-count existing-contributor) u1),
            })
            (map-set contributors contributor {
                total-contributed: amount,
                contribution-count: u1,
            })
        )
        (ok true)
    )
)

(define-public (request-loan (amount uint))
    (let (
            (farmer tx-sender)
            (loan-id (var-get next-loan-id))
            (dynamic-rate (calculate-dynamic-interest-rate farmer))
            (interest-amount (/ (* amount dynamic-rate) u100))
        )
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-some (map-get? farmers farmer)) ERR_FARMER_NOT_REGISTERED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (var-get total-fund-balance)) ERR_INSUFFICIENT_FUNDS)
        (map-set loans loan-id {
            farmer: farmer,
            amount: amount,
            interest: interest-amount,
            requested-at: stacks-block-height,
            approved-at: none,
            due-at: none,
            repaid-at: none,
            approved: false,
            repaid: false,
        })
        (initialize-loan-alerts loan-id)
        (var-set next-loan-id (+ loan-id u1))
        (ok loan-id)
    )
)

(define-public (approve-loan (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) ERR_LOAN_NOT_FOUND)))
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (not (get approved loan)) ERR_LOAN_ALREADY_APPROVED)
        (let (
                (farmer (get farmer loan))
                (amount (get amount loan))
                (due-block (+ stacks-block-height (var-get loan-duration-blocks)))
            )
            (try! (as-contract (stx-transfer? amount tx-sender farmer)))
            (var-set total-fund-balance (- (var-get total-fund-balance) amount))
            (map-set loans loan-id
                (merge loan {
                    approved-at: (some stacks-block-height),
                    due-at: (some due-block),
                    approved: true,
                })
            )
            (match (map-get? farmers farmer)
                farmer-data (begin
                    (map-set farmers farmer
                        (merge farmer-data {
                            total-borrowed: (+ (get total-borrowed farmer-data) amount),
                            active-loans: (+ (get active-loans farmer-data) u1),
                            total-loans: (+ (get total-loans farmer-data) u1),
                        })
                    )
                    true
                )
                false
            )
            (ok true)
        )
    )
)

(define-public (repay-loan (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) ERR_LOAN_NOT_FOUND)))
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender (get farmer loan)) ERR_UNAUTHORIZED)
        (asserts! (get approved loan) ERR_LOAN_NOT_APPROVED)
        (asserts! (not (get repaid loan)) ERR_LOAN_ALREADY_REPAID)
        (let (
                (repayment-amount (+ (get amount loan) (get interest loan)))
                (farmer (get farmer loan))
            )
            (try! (stx-transfer? repayment-amount farmer (as-contract tx-sender)))
            (var-set total-fund-balance
                (+ (var-get total-fund-balance) repayment-amount)
            )
            (map-set loans loan-id
                (merge loan {
                    repaid-at: (some stacks-block-height),
                    repaid: true,
                })
            )
            (match (map-get? farmers farmer)
                farmer-data (begin
                    (let (
                            (new-successful-loans (+ (get successful-loans farmer-data) u1))
                            (total-loans (get total-loans farmer-data))
                            (new-score (if (> total-loans u0)
                                (/ (* new-successful-loans u100) total-loans)
                                u100
                            ))
                        )
                        (map-set farmers farmer
                            (merge farmer-data {
                                total-repaid: (+ (get total-repaid farmer-data)
                                    repayment-amount
                                ),
                                active-loans: (- (get active-loans farmer-data) u1),
                                successful-loans: new-successful-loans,
                                reputation-score: new-score,
                            })
                        )
                    )
                    true
                )
                false
            )
            (ok true)
        )
    )
)

(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (var-get total-fund-balance)) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set total-fund-balance (- (var-get total-fund-balance) amount))
        (ok true)
    )
)

(define-public (update-interest-rate (new-rate uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set interest-rate new-rate)
        (ok true)
    )
)

(define-public (update-base-interest-rate (new-rate uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set base-interest-rate new-rate)
        (ok true)
    )
)

(define-public (update-reputation-discount-rate (new-rate uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set reputation-discount-rate new-rate)
        (ok true)
    )
)

(define-public (update-loan-duration (new-duration uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set loan-duration-blocks new-duration)
        (ok true)
    )
)

(define-public (deposit-collateral (amount uint))
    (let ((depositor tx-sender))
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (is-none (map-get? collateral-deposits depositor))
            ERR_COLLATERAL_ALREADY_DEPOSITED
        )
        (try! (stx-transfer? amount depositor (as-contract tx-sender)))
        (map-set collateral-deposits depositor {
            amount: amount,
            deposited-at: stacks-block-height,
            locked: false,
            linked-loan: none,
        })
        (ok true)
    )
)

(define-public (withdraw-collateral)
    (let (
            (depositor tx-sender)
            (collateral (unwrap! (map-get? collateral-deposits depositor)
                ERR_COLLATERAL_NOT_FOUND
            ))
        )
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (not (get locked collateral)) ERR_UNAUTHORIZED)
        (let ((amount (get amount collateral)))
            (try! (as-contract (stx-transfer? amount tx-sender depositor)))
            (map-delete collateral-deposits depositor)
            (ok true)
        )
    )
)

(define-public (request-collateralized-loan (amount uint))
    (let (
            (farmer tx-sender)
            (loan-id (var-get next-loan-id))
            (dynamic-rate (calculate-dynamic-interest-rate farmer))
            (interest-amount (/ (* amount dynamic-rate) u100))
            (collateral (unwrap! (map-get? collateral-deposits farmer)
                ERR_COLLATERAL_NOT_FOUND
            ))
            (required-collateral (/ (* amount (var-get collateral-ratio)) u100))
        )
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-some (map-get? farmers farmer)) ERR_FARMER_NOT_REGISTERED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount (var-get total-fund-balance)) ERR_INSUFFICIENT_FUNDS)
        (asserts! (not (get locked collateral)) ERR_UNAUTHORIZED)
        (asserts! (>= (get amount collateral) required-collateral)
            ERR_INSUFFICIENT_COLLATERAL
        )
        (map-set loans loan-id {
            farmer: farmer,
            amount: amount,
            interest: interest-amount,
            requested-at: stacks-block-height,
            approved-at: none,
            due-at: none,
            repaid-at: none,
            approved: false,
            repaid: false,
        })
        (initialize-loan-alerts loan-id)
        (map-set collateral-deposits farmer
            (merge collateral {
                locked: true,
                linked-loan: (some loan-id),
            })
        )
        (var-set next-loan-id (+ loan-id u1))
        (ok loan-id)
    )
)

(define-public (liquidate-collateral (loan-id uint))
    (let (
            (loan (unwrap! (map-get? loans loan-id) ERR_LOAN_NOT_FOUND))
            (farmer (get farmer loan))
            (collateral (unwrap! (map-get? collateral-deposits farmer)
                ERR_COLLATERAL_NOT_FOUND
            ))
        )
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (get approved loan) ERR_LOAN_NOT_APPROVED)
        (asserts! (not (get repaid loan)) ERR_LOAN_ALREADY_REPAID)
        (asserts! (is-loan-overdue loan-id) ERR_UNAUTHORIZED)
        (let (
                (debt-amount (+ (get amount loan) (get interest loan)))
                (liquidation-amount (if (<= (get amount collateral) debt-amount)
                    (get amount collateral)
                    debt-amount
                ))
            )
            (var-set total-fund-balance
                (+ (var-get total-fund-balance) liquidation-amount)
            )
            (map-set collateral-deposits farmer
                (merge collateral {
                    amount: (- (get amount collateral) liquidation-amount),
                    locked: false,
                    linked-loan: none,
                })
            )
            (map-set loans loan-id
                (merge loan {
                    repaid-at: (some stacks-block-height),
                    repaid: true,
                })
            )
            (match (map-get? farmers farmer)
                farmer-data (begin
                    (map-set farmers farmer
                        (merge farmer-data {
                            total-repaid: (+ (get total-repaid farmer-data) liquidation-amount),
                            active-loans: (- (get active-loans farmer-data) u1),
                        })
                    )
                    true
                )
                false
            )
            (ok liquidation-amount)
        )
    )
)

(define-public (update-collateral-ratio (new-ratio uint))
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set collateral-ratio new-ratio)
        (ok true)
    )
)

;; === LOAN ALERT SYSTEM FUNCTIONS ===

;; Update alert threshold settings (owner only)
(define-public (update-alert-thresholds
        (seven-day uint)
        (three-day uint)
        (one-day uint)
        (fund-threshold uint)
    )
    (begin
        (asserts! (not (get paused (var-get contract-pause-state)))
            ERR_CONTRACT_PAUSED
        )
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (> seven-day three-day) ERR_INVALID_ALERT_THRESHOLD)
        (asserts! (> three-day one-day) ERR_INVALID_ALERT_THRESHOLD)
        (asserts! (> one-day u0) ERR_INVALID_ALERT_THRESHOLD)
        (asserts! (> fund-threshold u0) ERR_INVALID_ALERT_THRESHOLD)
        (var-set alert-settings {
            seven-day-threshold: seven-day,
            three-day-threshold: three-day,
            one-day-threshold: one-day,
            fund-low-balance-threshold: fund-threshold,
            enabled: true,
        })
        (ok true)
    )
)

;; Initialize loan alerts for a new loan
(define-private (initialize-loan-alerts (loan-id uint))
    (map-set loan-alerts { loan-id: loan-id } {
        seven-day-alert: false,
        three-day-alert: false,
        one-day-alert: false,
        overdue-alert: false,
        last-check: stacks-block-height,
    })
)

;; Check loan due dates and identify those approaching deadlines
(define-read-only (check-loan-due-dates (loan-id uint))
    (match (map-get? loans loan-id)
        loan (match (get due-at loan)
            due-block (if (and (get approved loan) (not (get repaid loan)))
                (let (
                        (current-block stacks-block-height)
                        (blocks-remaining (if (> due-block current-block)
                            (- due-block current-block)
                            u0
                        ))
                        (settings (var-get alert-settings))
                    )
                    (some {
                        loan-id: loan-id,
                        due-block: due-block,
                        blocks-remaining: blocks-remaining,
                        seven-day-warning: (and (> blocks-remaining u0) (<= blocks-remaining (get seven-day-threshold settings))),
                        three-day-warning: (and (> blocks-remaining u0) (<= blocks-remaining (get three-day-threshold settings))),
                        one-day-warning: (and (> blocks-remaining u0) (<= blocks-remaining (get one-day-threshold settings))),
                        overdue: (is-eq blocks-remaining u0),
                    })
                )
                none
            )
            none
        )
        none
    )
)

;; Generate comprehensive loan status report
(define-read-only (generate-loan-status-report (loan-id uint))
    (match (map-get? loans loan-id)
        loan (let (
                (farmer (get farmer loan))
                (due-dates (check-loan-due-dates loan-id))
                (risk-assessment (get-loan-risk-assessment loan-id))
                (repayment-amount (calculate-repayment-amount loan-id))
            )
            (some {
                loan-id: loan-id,
                farmer: farmer,
                amount: (get amount loan),
                interest: (get interest loan),
                approved: (get approved loan),
                repaid: (get repaid loan),
                requested-at: (get requested-at loan),
                approved-at: (get approved-at loan),
                due-at: (get due-at loan),
                repaid-at: (get repaid-at loan),
                due-date-info: due-dates,
                risk-level: risk-assessment,
                total-repayment: repayment-amount,
            })
        )
        none
    )
)

;; Get overdue loan summary with statistics
(define-read-only (get-overdue-loan-summary)
    (let (
            (current-block stacks-block-height)
            (total-loans (- (var-get next-loan-id) u1))
        )
        ;; Note: In a real implementation, we would iterate through all loans
        ;; For this demo, we provide the structure for overdue loan tracking
        {
            total-loans: total-loans,
            overdue-count: u0, ;; Would be calculated by iterating through all active loans
            total-overdue-amount: u0, ;; Sum of all overdue loan amounts
            average-days-overdue: u0, ;; Average overdue period
            last-updated: current-block,
        }
    )
)

;; Calculate comprehensive fund health score (0-100)
(define-read-only (calculate-fund-health-score)
    (let (
            (fund-balance (var-get total-fund-balance))
            (settings (var-get alert-settings))
            (fund-threshold (get fund-low-balance-threshold settings))
            (total-loans (- (var-get next-loan-id) u1))
            ;; Balance score (40% weight): Higher balance = better score
            (balance-score (if (>= fund-balance fund-threshold)
                u40
                (/ (* fund-balance u40) fund-threshold)
            ))
            ;; Activity score (30% weight): Having loans shows activity
            (activity-score (if (> total-loans u0)
                u30
                u0
            ))
            ;; Stability score (30% weight): Lower overdue rate = higher score
            (stability-score u30) ;; Simplified - would calculate based on overdue rates
        )
        {
            overall-score: (+ (+ balance-score activity-score) stability-score),
            balance-score: balance-score,
            activity-score: activity-score,
            stability-score: stability-score,
            fund-balance: fund-balance,
            total-loans: total-loans,
            last-calculated: stacks-block-height,
        }
    )
)

;; Get loan risk assessment based on farmer reputation and loan details
(define-read-only (get-loan-risk-assessment (loan-id uint))
    (match (map-get? loans loan-id)
        loan (let (
                (farmer (get farmer loan))
                (loan-amount (get amount loan))
                (fund-balance (var-get total-fund-balance))
            )
            (match (map-get? farmers farmer)
                farmer-data (let (
                        (reputation (get reputation-score farmer-data))
                        (total-borrowed (get total-borrowed farmer-data))
                        (successful-loans (get successful-loans farmer-data))
                        (total-farmer-loans (get total-loans farmer-data))
                        ;; Risk factors calculation
                        (reputation-risk (if (>= reputation u75)
                            u10
                            (if (>= reputation u50)
                                u25
                                u40
                            )
                        ))
                        (amount-risk (if (> (* loan-amount u10) fund-balance)
                            u30
                            u10
                        ))
                        (history-risk (if (and
                                (> total-farmer-loans u0)
                                (>=
                                    (/ (* successful-loans u100)
                                        total-farmer-loans
                                    )
                                    u80
                                )
                            )
                            u5
                            u20
                        ))
                        (total-risk (+ (+ reputation-risk amount-risk) history-risk))
                    )
                    (some {
                        loan-id: loan-id,
                        farmer: farmer,
                        reputation-score: reputation,
                        reputation-risk: reputation-risk,
                        amount-risk: amount-risk,
                        history-risk: history-risk,
                        total-risk-score: total-risk,
                        risk-level: (if (<= total-risk u20)
                            "LOW"
                            (if (<= total-risk u50)
                                "MEDIUM"
                                "HIGH"
                            )
                        ),
                    })
                )
                none
            )
        )
        none
    )
)

;; Check if fund balance is critically low
(define-read-only (trigger-fund-low-balance-alert)
    (let (
            (current-balance (var-get total-fund-balance))
            (settings (var-get alert-settings))
            (threshold (get fund-low-balance-threshold settings))
        )
        {
            alert-triggered: (< current-balance threshold),
            current-balance: current-balance,
            threshold: threshold,
            deficit: (if (< current-balance threshold)
                (- threshold current-balance)
                u0
            ),
            percentage-of-threshold: (if (> threshold u0)
                (/ (* current-balance u100) threshold)
                u0
            ),
        }
    )
)

;; Get current alert settings
(define-read-only (get-alert-settings)
    (var-get alert-settings)
)

;; Get fund health metrics
(define-read-only (get-fund-health-metrics)
    (var-get fund-health-metrics)
)

;; Get loan alert status
(define-read-only (get-loan-alert-status (loan-id uint))
    (map-get? loan-alerts { loan-id: loan-id })
)

(define-read-only (get-fund-balance)
    (var-get total-fund-balance)
)

(define-read-only (get-loan-info (loan-id uint))
    (map-get? loans loan-id)
)

(define-read-only (get-farmer-info (farmer principal))
    (map-get? farmers farmer)
)

(define-read-only (get-contributor-info (contributor principal))
    (map-get? contributors contributor)
)

(define-read-only (get-interest-rate)
    (var-get interest-rate)
)

(define-read-only (get-loan-duration)
    (var-get loan-duration-blocks)
)

(define-read-only (is-loan-overdue (loan-id uint))
    (match (map-get? loans loan-id)
        loan (match (get due-at loan)
            due-block (if (and (get approved loan) (not (get repaid loan)))
                (> stacks-block-height due-block)
                false
            )
            false
        )
        false
    )
)

(define-read-only (calculate-repayment-amount (loan-id uint))
    (match (map-get? loans loan-id)
        loan (some (+ (get amount loan) (get interest loan)))
        none
    )
)

(define-read-only (get-farmer-active-loans (farmer principal))
    (match (map-get? farmers farmer)
        farmer-data (some (get active-loans farmer-data))
        none
    )
)

(define-read-only (get-next-loan-id)
    (var-get next-loan-id)
)

(define-read-only (get-collateral-info (depositor principal))
    (map-get? collateral-deposits depositor)
)

(define-read-only (get-collateral-ratio)
    (var-get collateral-ratio)
)

(define-read-only (calculate-required-collateral (loan-amount uint))
    (/ (* loan-amount (var-get collateral-ratio)) u100)
)

(define-read-only (calculate-dynamic-interest-rate (farmer principal))
    (match (map-get? farmers farmer)
        farmer-data (let (
                (reputation (get reputation-score farmer-data))
                (base-rate (var-get base-interest-rate))
                (discount-rate (var-get reputation-discount-rate))
                (tier (get-reputation-tier reputation))
                (discount-multiplier (if (is-eq tier u1)
                    u0
                    (if (is-eq tier u2)
                        u1
                        (if (is-eq tier u3)
                            u2
                            u3
                        )
                    )
                ))
            )
            (if (<= (* discount-multiplier discount-rate) base-rate)
                (- base-rate (* discount-multiplier discount-rate))
                base-rate
            )
        )
        (var-get base-interest-rate)
    )
)

(define-read-only (get-reputation-tier (score uint))
    (if (>= score u90)
        u4
        (if (>= score u75)
            u3
            (if (>= score u60)
                u2
                u1
            )
        )
    )
)

(define-read-only (get-farmer-reputation (farmer principal))
    (match (map-get? farmers farmer)
        farmer-data (some {
            reputation-score: (get reputation-score farmer-data),
            successful-loans: (get successful-loans farmer-data),
            total-loans: (get total-loans farmer-data),
            reputation-tier: (get-reputation-tier (get reputation-score farmer-data)),
        })
        none
    )
)

(define-read-only (get-base-interest-rate)
    (var-get base-interest-rate)
)

(define-read-only (get-reputation-discount-rate)
    (var-get reputation-discount-rate)
)

(define-public (set-contract-pause-state
        (paused bool)
        (reason (string-ascii 100))
    )
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set contract-pause-state {
            paused: paused,
            reason: reason,
            since-block: stacks-block-height,
        })
        (ok true)
    )
)

(define-read-only (get-contract-pause-state)
    (var-get contract-pause-state)
)
