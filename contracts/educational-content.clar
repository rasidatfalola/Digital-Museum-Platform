;; Educational Content Contract
;; Manages guided tours, learning materials, and educational resources

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-CONTENT-NOT-FOUND (err u301))
(define-constant ERR-CONTENT-EXISTS (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-TOUR-NOT-ACTIVE (err u304))

;; Data Variables
(define-data-var next-content-id uint u1)
(define-data-var next-tour-id uint u1)

;; Data Maps
(define-map educational-content
  { content-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    content-type: (string-ascii 20),
    creator: principal,
    difficulty-level: uint,
    estimated-duration: uint,
    is-active: bool,
    completion-count: uint
  }
)

(define-map guided-tours
  { tour-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    guide: principal,
    max-participants: uint,
    current-participants: uint,
    start-time: uint,
    duration: uint,
    is-active: bool
  }
)

(define-map tour-participants
  { tour-id: uint, participant: principal }
  {
    joined-at: uint,
    completed: bool,
    rating: uint
  }
)

(define-map learning-progress
  { user: principal, content-id: uint }
  {
    progress-percentage: uint,
    started-at: uint,
    completed-at: uint,
    quiz-score: uint
  }
)

;; Authorization check
(define-private (is-authorized (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (is-educator caller)))

;; Check if user is an educator
(define-private (is-educator (user principal))
  (is-eq user tx-sender))

;; Create educational content
(define-public (create-content (title (string-ascii 100))
                              (description (string-ascii 500))
                              (content-type (string-ascii 20))
                              (difficulty-level uint)
                              (estimated-duration uint))
  (let ((content-id (var-get next-content-id)))
    (asserts! (> (len title) u0) ERR-INVALID-INPUT)
    (asserts! (<= difficulty-level u5) ERR-INVALID-INPUT)
    (asserts! (> difficulty-level u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? educational-content { content-id: content-id })) ERR-CONTENT-EXISTS)

    (map-set educational-content
      { content-id: content-id }
      {
        title: title,
        description: description,
        content-type: content-type,
        creator: tx-sender,
        difficulty-level: difficulty-level,
        estimated-duration: estimated-duration,
        is-active: true,
        completion-count: u0
      })

    (var-set next-content-id (+ content-id u1))
    (ok content-id)))

;; Create guided tour
(define-public (create-guided-tour (name (string-ascii 100))
                                  (description (string-ascii 500))
                                  (max-participants uint)
                                  (start-time uint)
                                  (duration uint))
  (let ((tour-id (var-get next-tour-id)))
    (asserts! (> (len name) u0) ERR-INVALID-INPUT)
    (asserts! (> max-participants u0) ERR-INVALID-INPUT)
    (asserts! (> start-time block-height) ERR-INVALID-INPUT)

    (map-set guided-tours
      { tour-id: tour-id }
      {
        name: name,
        description: description,
        guide: tx-sender,
        max-participants: max-participants,
        current-participants: u0,
        start-time: start-time,
        duration: duration,
        is-active: true
      })

    (var-set next-tour-id (+ tour-id u1))
    (ok tour-id)))

;; Join guided tour
(define-public (join-tour (tour-id uint))
  (let ((tour (unwrap! (map-get? guided-tours { tour-id: tour-id }) ERR-CONTENT-NOT-FOUND)))
    (asserts! (get is-active tour) ERR-TOUR-NOT-ACTIVE)
    (asserts! (< (get current-participants tour) (get max-participants tour)) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? tour-participants { tour-id: tour-id, participant: tx-sender })) ERR-CONTENT-EXISTS)

    (map-set tour-participants
      { tour-id: tour-id, participant: tx-sender }
      {
        joined-at: block-height,
        completed: false,
        rating: u0
      })

    (map-set guided-tours
      { tour-id: tour-id }
      (merge tour {
        current-participants: (+ (get current-participants tour) u1)
      }))

    (ok true)))

;; Start learning content
(define-public (start-learning (content-id uint))
  (let ((content (unwrap! (map-get? educational-content { content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
    (asserts! (get is-active content) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? learning-progress { user: tx-sender, content-id: content-id })) ERR-CONTENT-EXISTS)

    (map-set learning-progress
      { user: tx-sender, content-id: content-id }
      {
        progress-percentage: u0,
        started-at: block-height,
        completed-at: u0,
        quiz-score: u0
      })

    (ok true)))

;; Update learning progress
(define-public (update-progress (content-id uint) (progress-percentage uint))
  (let ((progress (unwrap! (map-get? learning-progress { user: tx-sender, content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
    (asserts! (<= progress-percentage u100) ERR-INVALID-INPUT)

    (map-set learning-progress
      { user: tx-sender, content-id: content-id }
      (merge progress {
        progress-percentage: progress-percentage,
        completed-at: (if (is-eq progress-percentage u100) block-height u0)
      }))

    (if (is-eq progress-percentage u100)
      (let ((content (unwrap! (map-get? educational-content { content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
        (map-set educational-content
          { content-id: content-id }
          (merge content {
            completion-count: (+ (get completion-count content) u1)
          }))
        (ok true))
      (ok true))))

;; Rate content
(define-public (rate-content (content-id uint) (rating uint))
  (let ((progress (unwrap! (map-get? learning-progress { user: tx-sender, content-id: content-id }) ERR-CONTENT-NOT-FOUND)))
    (asserts! (<= rating u5) ERR-INVALID-INPUT)
    (asserts! (> rating u0) ERR-INVALID-INPUT)
    (asserts! (> (get progress-percentage progress) u50) ERR-NOT-AUTHORIZED)

    (ok true)))

;; Read-only functions
(define-read-only (get-content (content-id uint))
  (map-get? educational-content { content-id: content-id }))

(define-read-only (get-tour (tour-id uint))
  (map-get? guided-tours { tour-id: tour-id }))

(define-read-only (get-learning-progress (user principal) (content-id uint))
  (map-get? learning-progress { user: user, content-id: content-id }))

(define-read-only (get-tour-participation (tour-id uint) (participant principal))
  (map-get? tour-participants { tour-id: tour-id, participant: participant }))

(define-read-only (get-next-content-id)
  (var-get next-content-id))

(define-read-only (get-next-tour-id)
  (var-get next-tour-id))
