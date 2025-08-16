;; Carbon Tracking Contract
;; Carbon footprint tracking and offset verification for sustainable mining operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-INPUT (err u301))
(define-constant ERR-EMISSION-SOURCE-NOT-FOUND (err u302))
(define-constant ERR-INVALID-TIMESTAMP (err u303))
(define-constant ERR-OFFSET-NOT-VERIFIED (err u304))
(define-constant ERR-INSUFFICIENT-OFFSETS (err u305))
(define-constant ERR-ALREADY-RETIRED (err u306))

;; Carbon emission targets and thresholds (in kg CO2e, scaled by 100)
(define-constant ANNUAL-EMISSION-TARGET u500000000) ;; 5,000,000 kg CO2e per year
(define-constant RENEWABLE-ENERGY-TARGET u8000)     ;; 80% renewable energy target
(define-constant OFFSET-BUFFER-PERCENTAGE u1100)    ;; 110% offset buffer for verification
(define-constant MAX-SCOPE3-RATIO u5000)           ;; Max 50% of total emissions from scope 3

;; Data Variables
(define-data-var next-emission-source-id uint u1)
(define-data-var next-emission-record-id uint u1)
(define-data-var next-offset-batch-id uint u1)
(define-data-var total-annual-emissions uint u0)
(define-data-var total-verified-offsets uint u0)

;; Maps
(define-map authorized-operators principal bool)
(define-map carbon-auditors principal bool)
(define-map emission-sources uint {
    source-name: (string-ascii 50),
    source-type: (string-ascii 30), ;; "equipment", "transport", "energy", "process", "fugitive"
    site-id: uint,
    emission-factor: uint, ;; kg CO2e per unit
    activity-unit: (string-ascii 20), ;; "liters", "kwh", "tonnes", "hours"
    operator: principal,
    created-at: uint,
    active: bool
})

(define-map emission-records uint {
    emission-source-id: uint,
    timestamp: uint,
    activity-amount: uint,
    scope-1-emissions: uint, ;; Direct emissions
    scope-2-emissions: uint, ;; Indirect energy emissions
    scope-3-emissions: uint, ;; Other indirect emissions
    energy-consumption: uint, ;; kWh
    renewable-percentage: uint, ;; Percentage of renewable energy used
    recorded-by: principal,
    verified: bool
})

(define-map carbon-offset-batches uint {
    batch-id: (string-ascii 50),
    project-name: (string-ascii 100),
    project-type: (string-ascii 50), ;; "forestry", "renewable", "methane-capture", "direct-air-capture"
    vintage-year: uint,
    total-credits: uint, ;; in kg CO2e
    retired-credits: uint,
    verification-standard: (string-ascii 30), ;; "VCS", "CDM", "Gold-Standard", "CAR"
    purchase-date: uint,
    purchase-price: uint, ;; in cents per tonne
    verified: bool,
    retired: bool
})

(define-map energy-consumption-records uint {
    site-id: uint,
    timestamp: uint,
    total-consumption: uint, ;; kWh
    grid-electricity: uint,
    renewable-solar: uint,
    renewable-wind: uint,
    renewable-hydro: uint,
    fossil-diesel: uint,
    fossil-natural-gas: uint,
    fossil-coal: uint,
    recorded-by: principal
})

(define-map carbon-reduction-projects uint {
    project-name: (string-ascii 100),
    project-type: (string-ascii 50),
    site-id: uint,
    start-date: uint,
    target-completion: uint,
    estimated-reduction: uint, ;; kg CO2e per year
    actual-reduction: uint,
    investment-amount: uint,
    status: (string-ascii 20), ;; "planned", "active", "completed", "cancelled"
    responsible-party: principal
})

(define-map net-zero-commitments uint {
    site-id: uint,
    target-year: uint,
    baseline-emissions: uint, ;; kg CO2e
    current-emissions: uint,
    reduction-percentage: uint,
    offset-percentage: uint,
    milestone-targets: {
        year-2025: uint,
        year-2030: uint,
        year-2035: uint,
        year-2040: uint
    },
    committed-date: uint,
    responsible-officer: principal
})

;; Authorization functions
(define-public (authorize-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set authorized-operators operator true))
    )
)

(define-public (authorize-carbon-auditor (auditor principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set carbon-auditors auditor true))
    )
)

(define-public (revoke-operator (operator principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-delete authorized-operators operator))
    )
)

;; Emission source management
(define-public (register-emission-source
    (source-name (string-ascii 50))
    (source-type (string-ascii 30))
    (site-id uint)
    (emission-factor uint)
    (activity-unit (string-ascii 20)))
    (let ((source-id (var-get next-emission-source-id)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (> (len source-name) u0) ERR-INVALID-INPUT)
        (asserts! (is-valid-source-type source-type) ERR-INVALID-INPUT)
        (asserts! (> emission-factor u0) ERR-INVALID-INPUT)

        (map-set emission-sources source-id {
            source-name: source-name,
            source-type: source-type,
            site-id: site-id,
            emission-factor: emission-factor,
            activity-unit: activity-unit,
            operator: tx-sender,
            created-at: block-height,
            active: true
        })
        (var-set next-emission-source-id (+ source-id u1))
        (ok source-id)
    )
)

;; Emission recording
(define-public (record-emissions
    (emission-source-id uint)
    (activity-amount uint)
    (scope-1-emissions uint)
    (scope-2-emissions uint)
    (scope-3-emissions uint)
    (energy-consumption uint)
    (renewable-percentage uint))
    (let ((record-id (var-get next-emission-record-id))
          (source (unwrap! (map-get? emission-sources emission-source-id) ERR-EMISSION-SOURCE-NOT-FOUND)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (get active source) ERR-INVALID-INPUT)
        (asserts! (> activity-amount u0) ERR-INVALID-INPUT)
        (asserts! (<= renewable-percentage u10000) ERR-INVALID-INPUT)
        (asserts! (validate-emission-data scope-1-emissions scope-2-emissions scope-3-emissions) ERR-INVALID-INPUT)

        (map-set emission-records record-id {
            emission-source-id: emission-source-id,
            timestamp: block-height,
            activity-amount: activity-amount,
            scope-1-emissions: scope-1-emissions,
            scope-2-emissions: scope-2-emissions,
            scope-3-emissions: scope-3-emissions,
            energy-consumption: energy-consumption,
            renewable-percentage: renewable-percentage,
            recorded-by: tx-sender,
            verified: false
        })

        ;; Update total annual emissions
        (let ((total-emissions (+ scope-1-emissions (+ scope-2-emissions scope-3-emissions))))
            (var-set total-annual-emissions (+ (var-get total-annual-emissions) total-emissions))
        )

        (var-set next-emission-record-id (+ record-id u1))
        (ok record-id)
    )
)

;; Energy consumption tracking
(define-public (record-energy-consumption
    (site-id uint)
    (grid-electricity uint)
    (renewable-solar uint)
    (renewable-wind uint)
    (renewable-hydro uint)
    (fossil-diesel uint)
    (fossil-natural-gas uint)
    (fossil-coal uint))
    (let ((energy-id (var-get next-emission-record-id)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)

        (let ((total-consumption (+ grid-electricity (+ renewable-solar (+ renewable-wind (+ renewable-hydro (+ fossil-diesel (+ fossil-natural-gas fossil-coal))))))))
            (asserts! (> total-consumption u0) ERR-INVALID-INPUT)

            (map-set energy-consumption-records energy-id {
                site-id: site-id,
                timestamp: block-height,
                total-consumption: total-consumption,
                grid-electricity: grid-electricity,
                renewable-solar: renewable-solar,
                renewable-wind: renewable-wind,
                renewable-hydro: renewable-hydro,
                fossil-diesel: fossil-diesel,
                fossil-natural-gas: fossil-natural-gas,
                fossil-coal: fossil-coal,
                recorded-by: tx-sender
            })

            (var-set next-emission-record-id (+ energy-id u1))
            (ok energy-id)
        )
    )
)

;; Carbon offset management
(define-public (register-offset-batch
    (batch-id (string-ascii 50))
    (project-name (string-ascii 100))
    (project-type (string-ascii 50))
    (vintage-year uint)
    (total-credits uint)
    (verification-standard (string-ascii 30))
    (purchase-price uint))
    (let ((offset-id (var-get next-offset-batch-id)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (> (len batch-id) u0) ERR-INVALID-INPUT)
        (asserts! (> (len project-name) u0) ERR-INVALID-INPUT)
        (asserts! (is-valid-project-type project-type) ERR-INVALID-INPUT)
        (asserts! (> total-credits u0) ERR-INVALID-INPUT)
        (asserts! (>= vintage-year u2020) ERR-INVALID-INPUT)

        (map-set carbon-offset-batches offset-id {
            batch-id: batch-id,
            project-name: project-name,
            project-type: project-type,
            vintage-year: vintage-year,
            total-credits: total-credits,
            retired-credits: u0,
            verification-standard: verification-standard,
            purchase-date: block-height,
            purchase-price: purchase-price,
            verified: false,
            retired: false
        })

        (var-set next-offset-batch-id (+ offset-id u1))
        (ok offset-id)
    )
)

(define-public (verify-offset-batch (offset-id uint))
    (let ((batch (unwrap! (map-get? carbon-offset-batches offset-id) ERR-INVALID-INPUT)))
        (asserts! (default-to false (map-get? carbon-auditors tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (not (get verified batch)) ERR-INVALID-INPUT)

        (let ((updated-batch (merge batch { verified: true })))
            (map-set carbon-offset-batches offset-id updated-batch)
            (var-set total-verified-offsets (+ (var-get total-verified-offsets) (get total-credits batch)))
            (ok true)
        )
    )
)

(define-public (retire-offset-credits (offset-id uint) (credits-to-retire uint))
    (let ((batch (unwrap! (map-get? carbon-offset-batches offset-id) ERR-INVALID-INPUT)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (get verified batch) ERR-OFFSET-NOT-VERIFIED)
        (asserts! (not (get retired batch)) ERR-ALREADY-RETIRED)
        (asserts! (<= credits-to-retire (- (get total-credits batch) (get retired-credits batch))) ERR-INSUFFICIENT-OFFSETS)

        (let ((new-retired-credits (+ (get retired-credits batch) credits-to-retire)))
            (map-set carbon-offset-batches offset-id (merge batch {
                retired-credits: new-retired-credits,
                retired: (is-eq new-retired-credits (get total-credits batch))
            }))
            (ok new-retired-credits)
        )
    )
)

;; Carbon reduction projects
(define-public (register-reduction-project
    (project-name (string-ascii 100))
    (project-type (string-ascii 50))
    (site-id uint)
    (target-completion uint)
    (estimated-reduction uint)
    (investment-amount uint))
    (let ((project-id (var-get next-emission-record-id)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (> (len project-name) u0) ERR-INVALID-INPUT)
        (asserts! (> target-completion block-height) ERR-INVALID-INPUT)
        (asserts! (> estimated-reduction u0) ERR-INVALID-INPUT)

        (map-set carbon-reduction-projects project-id {
            project-name: project-name,
            project-type: project-type,
            site-id: site-id,
            start-date: block-height,
            target-completion: target-completion,
            estimated-reduction: estimated-reduction,
            actual-reduction: u0,
            investment-amount: investment-amount,
            status: "planned",
            responsible-party: tx-sender
        })

        (var-set next-emission-record-id (+ project-id u1))
        (ok project-id)
    )
)

;; Net-zero commitment tracking
(define-public (commit-to-net-zero
    (site-id uint)
    (target-year uint)
    (baseline-emissions uint)
    (year-2025-target uint)
    (year-2030-target uint)
    (year-2035-target uint)
    (year-2040-target uint))
    (let ((commitment-id (var-get next-emission-record-id)))
        (asserts! (default-to false (map-get? authorized-operators tx-sender)) ERR-NOT-AUTHORIZED)
        (asserts! (>= target-year u2030) ERR-INVALID-INPUT)
        (asserts! (> baseline-emissions u0) ERR-INVALID-INPUT)
        (asserts! (validate-milestone-targets year-2025-target year-2030-target year-2035-target year-2040-target baseline-emissions) ERR-INVALID-INPUT)

        (map-set net-zero-commitments commitment-id {
            site-id: site-id,
            target-year: target-year,
            baseline-emissions: baseline-emissions,
            current-emissions: baseline-emissions,
            reduction-percentage: u0,
            offset-percentage: u0,
            milestone-targets: {
                year-2025: year-2025-target,
                year-2030: year-2030-target,
                year-2035: year-2035-target,
                year-2040: year-2040-target
            },
            committed-date: block-height,
            responsible-officer: tx-sender
        })

        (var-set next-emission-record-id (+ commitment-id u1))
        (ok commitment-id)
    )
)

;; Verification functions
(define-public (verify-emission-record (record-id uint))
    (let ((record (unwrap! (map-get? emission-records record-id) ERR-INVALID-INPUT)))
        (asserts! (default-to false (map-get? carbon-auditors tx-sender)) ERR-NOT-AUTHORIZED)
        (ok (map-set emission-records record-id (merge record { verified: true })))
    )
)

;; Private helper functions
(define-private (is-valid-source-type (source-type (string-ascii 30)))
    (or (is-eq source-type "equipment")
        (is-eq source-type "transport")
        (is-eq source-type "energy")
        (is-eq source-type "process")
        (is-eq source-type "fugitive"))
)

(define-private (is-valid-project-type (project-type (string-ascii 50)))
    (or (is-eq project-type "forestry")
        (is-eq project-type "renewable")
        (is-eq project-type "methane-capture")
        (is-eq project-type "direct-air-capture"))
)

(define-private (validate-emission-data (scope-1 uint) (scope-2 uint) (scope-3 uint))
    (let ((total-emissions (+ scope-1 (+ scope-2 scope-3))))
        (and
            (> total-emissions u0)
            (<= scope-3 (/ (* total-emissions MAX-SCOPE3-RATIO) u10000))
        )
    )
)

(define-private (validate-milestone-targets (t2025 uint) (t2030 uint) (t2035 uint) (t2040 uint) (baseline uint))
    (and
        (< t2025 baseline)
        (< t2030 t2025)
        (< t2035 t2030)
        (< t2040 t2035)
    )
)

;; Read-only functions
(define-read-only (get-emission-source (source-id uint))
    (map-get? emission-sources source-id)
)

(define-read-only (get-emission-record (record-id uint))
    (map-get? emission-records record-id)
)

(define-read-only (get-offset-batch (offset-id uint))
    (map-get? carbon-offset-batches offset-id)
)

(define-read-only (get-energy-consumption-record (energy-id uint))
    (map-get? energy-consumption-records energy-id)
)

(define-read-only (get-reduction-project (project-id uint))
    (map-get? carbon-reduction-projects project-id)
)

(define-read-only (get-net-zero-commitment (commitment-id uint))
    (map-get? net-zero-commitments commitment-id)
)

(define-read-only (get-total-annual-emissions)
    (var-get total-annual-emissions)
)

(define-read-only (get-total-verified-offsets)
    (var-get total-verified-offsets)
)

(define-read-only (calculate-net-emissions)
    (let ((total-emissions (var-get total-annual-emissions))
          (total-offsets (var-get total-verified-offsets)))
        (if (>= total-offsets total-emissions)
            u0
            (- total-emissions total-offsets))
    )
)

(define-read-only (is-authorized-operator (operator principal))
    (default-to false (map-get? authorized-operators operator))
)

(define-read-only (is-carbon-auditor (auditor principal))
    (default-to false (map-get? carbon-auditors auditor))
)

;; Initialize contract
(begin
    (map-set authorized-operators CONTRACT-OWNER true)
    (map-set carbon-auditors CONTRACT-OWNER true)
)
