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

(define-data-var total-fund-balance uint u0)
(define-data-var next-loan-id uint u1)
(define-data-var interest-rate uint u10)
(define-data-var loan-duration-blocks uint u4320)

(define-map farmers
    principal
    {
        name: (string-ascii 50),
        location: (string-ascii 100),
        registered-at: uint,
        total-borrowed: uint,
        total-repaid: uint,
        active-loans: uint,
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

(define-public (register-farmer
        (name (string-ascii 50))
        (location (string-ascii 100))
    )
    (let ((farmer tx-sender))
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
        })
        (ok true)
    )
)

(define-public (contribute-to-fund (amount uint))
    (let ((contributor tx-sender))
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
            (interest-amount (/ (* amount (var-get interest-rate)) u100))
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
        (var-set next-loan-id (+ loan-id u1))
        (ok loan-id)
    )
)

(define-public (approve-loan (loan-id uint))
    (let ((loan (unwrap! (map-get? loans loan-id) ERR_LOAN_NOT_FOUND)))
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
                    (map-set farmers farmer
                        (merge farmer-data {
                            total-repaid: (+ (get total-repaid farmer-data) repayment-amount),
                            active-loans: (- (get active-loans farmer-data) u1),
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

(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (var-get total-fund-balance)) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender CONTRACT_OWNER)))
        (var-set total-fund-balance (- (var-get total-fund-balance) amount))
        (ok true)
    )
)

(define-public (update-interest-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set interest-rate new-rate)
        (ok true)
    )
)

(define-public (update-loan-duration (new-duration uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (var-set loan-duration-blocks new-duration)
        (ok true)
    )
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
