import SpriteKit
import UIKit
import GameKit

class GameScene: SKScene {
    /// The game scene currently on screen, so app lifecycle hooks can reach it
    /// without walking UIApplication windows.
    static weak var active: GameScene?

    // MARK: - Fixed logical board
    /// Every device plays the same board so leaderboard scores are fair.
    /// Cell size is computed to fit; the board is letterboxed and centered.
    static let columns = 18
    static let rows = 32
    private let gridWidth = GameScene.columns
    private let gridHeight = GameScene.rows
    private static let saveVersion = 2

    // MARK: - Cosmetics (data-driven, see Cosmetics.swift)
    private var skin: Skin = EntitlementStore.shared.selectedSkin
    private var map: GameMap = EntitlementStore.shared.selectedMap
    private var snake: [(Int, Int)] = []
    private var food: SKSpriteNode?
    private var foodCell: (Int, Int)?
    private var moveDirection: CGVector = CGVector(dx: 1, dy: 0)
    private var nextMoveTime: TimeInterval = 0
    private var moveSpeed: TimeInterval = 0.13
    private var score: Int = 0
    private var scoreLabel: SKLabelNode?

    private var saveMessageLabel: SKLabelNode?

    private var level: Int = 1
    private var baseSpeed: TimeInterval = 0.13
    private let speedIncreaseFactor: Double = 0.85

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator()

    private var pauseButton: SKNode?
    private var gameTimer: Timer?
    private var startTime: TimeInterval = 0
    private var elapsedTime: TimeInterval = 0
    private var clockLabel: SKLabelNode!

    private var isGameOver: Bool = false
    private var isPausedGame: Bool = false

    // MARK: - Layout state (recomputed on resize / hinge change)
    private var cellSize: CGFloat = 22
    private var boardRect: CGRect = .zero
    private var hudRect: CGRect = .zero
    private var hingeInteraction: AnyObject?
    private var lastLayoutKey: String = ""

    override init(size: CGSize) {
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = .black
        computeLayout()
        setupClockLabel()
        setupGame()
        impactFeedbackGenerator.prepare()
        notificationFeedbackGenerator.prepare()

        addSwipeGestures(to: view)
        setupPauseButton()
        setupSaveMessageLabel()
        loadGameState()
        applyLayout()

        installHingeObserver(on: view)

        GameScene.active = self
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(appWillResignActive),
                       name: UIScene.willDeactivateNotification, object: nil)
        nc.addObserver(self, selector: #selector(appDidBecomeActive),
                       name: UIScene.didActivateNotification, object: nil)
    }

    override func willMove(from view: SKView) {
        NotificationCenter.default.removeObserver(self)
        if #available(iOS 27.1, *), let hinge = hingeInteraction as? UIHingeInteraction {
            view.removeInteraction(hinge)
        }
        hingeInteraction = nil
        if GameScene.active === self { GameScene.active = nil }
        super.willMove(from: view)
    }

    @objc private func appWillResignActive() { handleAppBackgrounded() }

    /// Save an in-progress run and pause it. Called on deactivate/background.
    func handleAppBackgrounded() {
        guard !isGameOver, !snake.isEmpty else { return }
        saveGameState()
        if !isPausedGame { pauseGame() }
    }

    @objc private func appDidBecomeActive() {
        // SKView un-pauses its scene when the app returns; keep our pause.
        if isPausedGame { isPaused = true }
        relayoutIfNeeded()
    }

    // MARK: - Layout (fixed grid + iPhone Duo fold awareness)

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        relayoutIfNeeded()
    }

    private func relayoutIfNeeded() {
        guard view != nil, size.width > 0, size.height > 0 else { return }
        computeLayout()
        applyLayout()
    }

    /// Hinge changes (book/laptop fold) can move the division without a size
    /// change, so listen for them explicitly. UIHingeInteraction is iOS 27.1+.
    private func installHingeObserver(on view: SKView) {
        guard hingeInteraction == nil else { return }
        if #available(iOS 27.1, *) {
            let interaction = UIHingeInteraction { [weak self] _, _ in
                // Region geometry settles after the hinge update; re-query next runloop too.
                self?.relayoutIfNeeded()
                DispatchQueue.main.async { self?.relayoutIfNeeded() }
            }
            view.addInteraction(interaction)
            hingeInteraction = interaction
        }
    }

    /// Active fold division in scene coordinates, if any (only when partially folded).
    private func activeDivisionRect() -> CGRect? {
        guard let view = view else { return nil }
        if #available(iOS 27.1, *) {
            guard let region = view.reservedRegions(kind: .division).first(where: { $0.isActive }) else { return nil }
            let f = region.frame // UIKit coords (y down); scene uses .resizeFill (1pt = 1unit, y up)
            guard f.width > 0 || f.height > 0 else { return nil }
            return CGRect(x: f.minX, y: size.height - f.maxY, width: f.width, height: f.height)
        }
        return nil
    }

    private func computeLayout() {
        let insets = view?.safeAreaInsets ?? .zero
        let safe = CGRect(x: insets.left,
                          y: insets.bottom,
                          width: max(0, size.width - insets.left - insets.right),
                          height: max(0, size.height - insets.top - insets.bottom))
        let pad: CGFloat = 8
        var playArea: CGRect
        let hudBand: CGFloat = 84

        if let division = activeDivisionRect(), division.intersects(safe) {
            if division.height >= division.width {
                // Book fold: vertical division → left | right.
                let left = CGRect(x: safe.minX, y: safe.minY, width: division.minX - safe.minX, height: safe.height)
                let right = CGRect(x: division.maxX, y: safe.minY, width: safe.maxX - division.maxX, height: safe.height)
                playArea = left.width >= right.width ? left : right
                hudRect = left.width >= right.width ? right : left
            } else {
                // Laptop fold: horizontal division → top (upright half) | bottom.
                let top = CGRect(x: safe.minX, y: division.maxY, width: safe.width, height: safe.maxY - division.maxY)
                let bottom = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: division.minY - safe.minY)
                playArea = top
                hudRect = bottom
            }
        } else {
            // Flat / no fold: board gets the full safe area under a slim HUD strip.
            hudRect = CGRect(x: safe.minX, y: safe.maxY - hudBand, width: safe.width, height: hudBand)
            playArea = CGRect(x: safe.minX, y: safe.minY, width: safe.width, height: safe.height - hudBand)
        }
        playArea = playArea.insetBy(dx: pad, dy: pad)

        let cell = max(4, floor(min(playArea.width / CGFloat(gridWidth), playArea.height / CGFloat(gridHeight))))
        cellSize = cell
        let w = cell * CGFloat(gridWidth), h = cell * CGFloat(gridHeight)
        boardRect = CGRect(x: (playArea.midX - w / 2).rounded(), y: (playArea.midY - h / 2).rounded(), width: w, height: h)
    }

    /// Reposition everything for the current board/HUD rects.
    private func applyLayout() {

        let hudTop = hudRect.maxY
        clockLabel?.position = CGPoint(x: hudRect.midX, y: hudTop - 34)
        scoreLabel?.position = CGPoint(x: hudRect.midX, y: hudTop - 56)
        pauseButton?.position = CGPoint(x: hudRect.maxX - 36, y: hudTop - 36)
        if hudRect.height > 200 {
            // HUD has its own half (fold): sit it in the middle of that half.
            clockLabel?.position = CGPoint(x: hudRect.midX, y: hudRect.midY + 30)
            scoreLabel?.position = CGPoint(x: hudRect.midX, y: hudRect.midY)
            pauseButton?.position = CGPoint(x: hudRect.midX, y: hudRect.midY - 60)
        }

        let center = CGPoint(x: boardRect.midX, y: boardRect.midY)
        childNode(withName: "pausedLabel")?.position = center
        childNode(withName: "quitLabel")?.position = CGPoint(x: center.x, y: center.y - 40)
        childNode(withName: "saveGameButton")?.position = CGPoint(x: center.x, y: center.y - 75)
        saveMessageLabel?.position = CGPoint(x: center.x, y: center.y - 100)

        if let cell = foodCell {
            food?.size = CGSize(width: cellSize, height: cellSize)
            food?.position = point(for: cell)
        }
        drawMap()
        updateSnakeDisplay()
    }

    /// Floor pattern + obstacles for the current map. No outline is drawn.
    private func drawMap() {
        childNode(withName: "mapLayer")?.removeFromParent()
        let layer = MapRenderer.board(for: map, cell: cellSize, previewFloor: false)
        layer.name = "mapLayer"
        layer.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
        layer.zPosition = -1
        addChild(layer)
    }

    private func isBlocked(_ cell: (Int, Int)) -> Bool {
        map.obstacles.contains(GridCell(cell.0, cell.1))
    }

    /// Classic start cell, moved if the map puts something on it or right in
    /// front of it (the snake starts heading right).
    private func startCell() -> (Int, Int) {
        let preferred = (Int(Double(gridWidth) * 0.6), Int(Double(gridHeight) * 0.7))
        func safe(_ c: (Int, Int)) -> Bool {
            for d in 0...4 {
                let x = c.0 + d
                if map.edges == .kill && x >= gridWidth { return false }
                if isBlocked(((x + gridWidth) % gridWidth, c.1)) { return false }
            }
            return true
        }
        if safe(preferred) { return preferred }
        var best: (Int, Int)?
        var bestDist = Int.max
        for x in 0..<gridWidth { for y in 0..<gridHeight where safe((x, y)) {
            let d = abs(x - preferred.0) + abs(y - preferred.1)
            if d < bestDist { bestDist = d; best = (x, y) }
        } }
        return best ?? preferred
    }

    /// Center of a grid cell in scene coordinates.
    private func point(for cell: (Int, Int)) -> CGPoint {
        CGPoint(x: boardRect.minX + (CGFloat(cell.0) + 0.5) * cellSize,
                y: boardRect.minY + (CGFloat(cell.1) + 0.5) * cellSize)
    }

    // MARK: - Input

    private func addSwipeGestures(to view: SKView) {
        for direction: UISwipeGestureRecognizer.Direction in [.up, .down, .left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipe(_:)))
            swipe.direction = direction
            view.addGestureRecognizer(swipe)
        }
    }

    @objc private func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
        switch gesture.direction {
        case .up:
            if moveDirection.dy == 0 { moveDirection = CGVector(dx: 0, dy: 1) }
        case .down:
            if moveDirection.dy == 0 { moveDirection = CGVector(dx: 0, dy: -1) }
        case .left:
            if moveDirection.dx == 0 { moveDirection = CGVector(dx: -1, dy: 0) }
        case .right:
            if moveDirection.dx == 0 { moveDirection = CGVector(dx: 1, dy: 0) }
        default:
            break
        }
    }

    private func setupSaveMessageLabel() {
        saveMessageLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
        saveMessageLabel?.fontSize = 20
        saveMessageLabel?.fontColor = .white
        saveMessageLabel?.position = CGPoint(x: boardRect.midX, y: boardRect.midY - 100)
        saveMessageLabel?.zPosition = 100
        saveMessageLabel?.isHidden = true
        addChild(saveMessageLabel!)
    }

    private func showSaveMessage() {
        saveMessageLabel?.text = "Game Saved!"
        saveMessageLabel?.isHidden = false
        let fadeOut = SKAction.fadeOut(withDuration: 2.0)
        let hideAction = SKAction.run { [weak self] in
            self?.saveMessageLabel?.isHidden = true
            self?.saveMessageLabel?.alpha = 1.0
        }
        saveMessageLabel?.run(SKAction.sequence([fadeOut, hideAction]))
    }

    private func addSaveGameButton() {
        let saveButton = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
        saveButton.text = "Save Game"
        saveButton.fontSize = 20
        saveButton.fontColor = .green
        saveButton.position = CGPoint(x: boardRect.midX, y: boardRect.midY - 75)
        saveButton.name = "saveGameButton"
        saveButton.zPosition = 100
        addChild(saveButton)
    }

    // MARK: - Game

    private func setupGame() {
        snake.removeAll()
        food?.removeFromParent()
        food = nil
        foodCell = nil
        score = 0
        level = 1
        moveSpeed = baseSpeed
        startTime = 0
        elapsedTime = 0

        if clockLabel == nil { setupClockLabel() }
        clockLabel.text = "00:00.000"
        if scoreLabel == nil { setupScoreLabel() }
        scoreLabel?.text = "Score: 0 | Level: 1"
        if pauseButton == nil { setupPauseButton() }

        moveDirection = CGVector(dx: 1, dy: 0)
        isGameOver = false

        // Same start cell as before (60% across, 70% up), unless the map blocks it.
        snake.insert(startCell(), at: 0)
        #if DEBUG
        // Testing only (screenshots): start with a longer snake trailing left,
        // with a couple of bends so the curve pieces show.
        if ProcessInfo.processInfo.arguments.contains("-slymeLongSnake"), let h = snake.first {
            let path = [(-1, 0), (-2, 0), (-3, 0), (-3, -1), (-3, -2), (-4, -2), (-5, -2),
                        (-5, -1), (-5, 0), (-6, 0), (-7, 0), (-8, 0)]
            for (dx, dy) in path {
                let c = (h.0 + dx, h.1 + dy)
                guard c.0 >= 0, c.1 >= 0, !isBlocked(c) else { break }
                snake.append(c)
            }
        }
        #endif
        spawnFood()
    }

    /// Place food on a random free cell (never on the snake).
    private func spawnFood() {
        food?.removeFromParent()
        let occupied = Set(snake.map { $0.0 * 10_000 + $0.1 })
        var free: [(Int, Int)] = []
        free.reserveCapacity(gridWidth * gridHeight)
        for x in 0..<gridWidth {
            for y in 0..<gridHeight where !occupied.contains(x * 10_000 + y) && !isBlocked((x, y)) {
                free.append((x, y))
            }
        }
        guard let cell = free.randomElement() else {
            // Board full: nothing left to eat.
            food = nil; foodCell = nil
            return
        }
        placeFood(at: cell)
    }

    private func placeFood(at cell: (Int, Int)) {
        food?.removeFromParent()
        let node = SKSpriteNode(texture: SKTexture(imageNamed: "apple"),
                                size: CGSize(width: cellSize, height: cellSize))
        node.position = point(for: cell)
        addChild(node)
        food = node
        foodCell = cell
    }

    private func setupScoreLabel() {
        scoreLabel = SKLabelNode(fontNamed: "CourierNewPS-BoldMT")
        scoreLabel?.fontSize = 16
        scoreLabel?.fontColor = .white
        scoreLabel?.position = CGPoint(x: hudRect.midX, y: hudRect.maxY - 56)
        scoreLabel?.text = "Score: 0 | Level: 1"
        addChild(scoreLabel!)
    }

    private func setupClockLabel() {
        clockLabel = SKLabelNode(text: "00:00.000")
        clockLabel.position = CGPoint(x: hudRect.midX, y: hudRect.maxY - 34)
        clockLabel.fontName = "CourierNewPS-BoldMT"
        clockLabel.fontColor = .white
        clockLabel.fontSize = 19
        addChild(clockLabel)
    }

    private func format(timeInterval: TimeInterval) -> String {
        let interval = Int(timeInterval)
        let seconds = interval % 60
        let minutes = (interval / 60) % 60
        let milliseconds = Int(timeInterval * 1000) % 1000
        return String(format: "%02d:%02d.%03d", minutes, seconds, milliseconds)
    }

    private func makePauseButton(playing: Bool) {
        let previous = pauseButton?.position
            ?? CGPoint(x: hudRect.maxX - 36, y: hudRect.maxY - 36)
        pauseButton?.removeFromParent()
        // playing == true means the game is paused, so show the play triangle.
        let button = PauseControl.make(playing: playing, at: previous)
        addChild(button)
        pauseButton = button
    }

    private func setupPauseButton() { makePauseButton(playing: false) }

    private func setupQuitButton() {
        guard childNode(withName: "quitLabel") == nil else { return }
        let quitLabel = SKLabelNode(text: "Quit?")
        quitLabel.fontName = "CourierNewPS-BoldMT"
        quitLabel.fontSize = 20
        quitLabel.fontColor = .red
        quitLabel.position = CGPoint(x: boardRect.midX, y: boardRect.midY - 40)
        quitLabel.zPosition = 100
        quitLabel.name = "quitLabel"
        addChild(quitLabel)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let nodesAtPoint = nodes(at: touch.location(in: self))

        if nodesAtPoint.contains(where: { $0.name == "pauseButton" }) {
            if isPausedGame { resumeGame() } else { pauseGame() }
        } else if nodesAtPoint.contains(where: { $0.name == "quitLabel" }) {
            showQuitConfirmation()
        }
        if nodesAtPoint.contains(where: { $0.name == "saveGameButton" }) {
            saveGameState()
            showSaveMessage()
        }
    }

    private func pauseGame() {
        guard !isPausedGame, !isGameOver else { return }
        isPausedGame = true
        self.isPaused = true
        stopClock()
        saveGameState()   // pause always checkpoints so quit / background can't lose the run
        makePauseButton(playing: true)

        if childNode(withName: "pausedLabel") == nil {
            let pausedLabel = SKLabelNode(text: "PAUSE")
            pausedLabel.fontName = "CourierNewPS-BoldMT"
            pausedLabel.fontSize = 40
            pausedLabel.position = CGPoint(x: boardRect.midX, y: boardRect.midY)
            pausedLabel.zPosition = 100
            pausedLabel.name = "pausedLabel"
            addChild(pausedLabel)
        }
        setupQuitButton()
        if childNode(withName: "saveGameButton") == nil { addSaveGameButton() }
    }

    private func showQuitConfirmation() {
        let alertController = UIAlertController(
            title: "Quit Game",
            message: "Are you sure you want to fold twin?",
            preferredStyle: .alert
        )
        alertController.addAction(UIAlertAction(title: "Quit", style: .destructive) { [weak self] _ in
            self?.quitGame()
        })
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        view?.window?.rootViewController?.present(alertController, animated: true, completion: nil)
    }

    private func quitGame() {
        cleanupScene()
        guard let view = self.view else { return }
        let mainMenuScene = MainMenu(size: view.bounds.size)
        mainMenuScene.scaleMode = .resizeFill
        view.presentScene(mainMenuScene, transition: SKTransition.fade(withDuration: 0.5))
    }

    private func resumeGame() {
        makePauseButton(playing: false)
        isPausedGame = false
        self.isPaused = false
        startTime = 0 // re-anchor the clock so paused time isn't counted
        childNode(withName: "pausedLabel")?.removeFromParent()
        childNode(withName: "quitLabel")?.removeFromParent()
        childNode(withName: "saveGameButton")?.removeFromParent()
    }

    override func update(_ currentTime: TimeInterval) {
        #if DEBUG
        // Testing only (screenshots): hold the snake still.
        if ProcessInfo.processInfo.arguments.contains("-slymeFreeze") { return }
        #endif
        if !isGameOver && !isPausedGame && !isPaused && currentTime > nextMoveTime {
            moveSnake()
            nextMoveTime = currentTime + moveSpeed
            if startTime == 0 {
                // Continue from any restored/paused elapsed time.
                startTime = currentTime - elapsedTime
            }
            elapsedTime = currentTime - startTime
            clockLabel.text = format(timeInterval: elapsedTime)
        }
    }

    private func moveSnake() {
        guard let head = snake.first else { return }
        let rawX = head.0 + Int(moveDirection.dx), rawY = head.1 + Int(moveDirection.dy)
        if map.edges == .kill && !((0..<gridWidth).contains(rawX) && (0..<gridHeight).contains(rawY)) {
            notificationFeedbackGenerator.notificationOccurred(.error)
            gameOver()
            return
        }
        let newHead = ((rawX + gridWidth) % gridWidth, (rawY + gridHeight) % gridHeight)

        if let foodCell = foodCell, newHead == foodCell {
            impactFeedbackGenerator.impactOccurred()
            snake.insert(newHead, at: 0)
            spawnFood()
            updateScore()
        } else {
            snake.insert(newHead, at: 0)
            snake.removeLast()
        }

        if checkForCollisions() {
            notificationFeedbackGenerator.notificationOccurred(.error)
            gameOver()
        }
        updateSnakeDisplay()
    }

    private func checkForCollisions() -> Bool {
        guard let head = snake.first else { return false }
        return isBlocked(head) || snake.dropFirst().contains { $0 == head }
    }

    private func updateScore() {
        score += 10
        let newLevel = (score / 50) + 1
        if newLevel != level {
            level = newLevel
            updateSpeedForLevel()
        }
        scoreLabel?.text = "Score: \(score) | Level: \(level)"
    }

    /// Speed steps up every third level (unchanged rule), derived from level so
    /// a restored game gets the right speed too.
    private func updateSpeedForLevel() {
        moveSpeed = max(baseSpeed * pow(speedIncreaseFactor, Double(level / 3)), 0.05)
    }

    private func gameOver() {
        isGameOver = true
        stopClock()
        showGameOverAlert()
        GameCenterManager.shared.submitScore(score)
        resetSavedGameState()
    }

    private func stopClock() {
        gameTimer?.invalidate()
        gameTimer = nil
    }

    private func showGameOverAlert() {
        let alertController = UIAlertController(title: "never backdoor yourself twin!", message: "you scored \(score) & reached level \(level).", preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "play again", style: .default) { [weak self] _ in
            self?.restartGame()
        })
        alertController.addAction(UIAlertAction(title: "share score", style: .default) { [weak self] _ in
            self?.shareScore()
        })
        alertController.addAction(UIAlertAction(title: "main menu", style: .default) { [weak self] _ in
            self?.goToMainMenu()
        })
        view?.window?.rootViewController?.present(alertController, animated: true, completion: nil)
    }

    private func restartGame() {
        cleanupScene()
        if let view = self.view { addSwipeGestures(to: view) }
        computeLayout()
        setupGame()
        applyLayout()
    }

    private func cleanupScene() {
        stopClock()
        removeAllChildren()
        removeAllActions()
        // Only remove our swipe recognizers; leave system/hinge interactions alone.
        view?.gestureRecognizers?.filter { $0 is UISwipeGestureRecognizer }.forEach { view?.removeGestureRecognizer($0) }

        gameTimer = nil
        clockLabel = nil
        pauseButton = nil
        food = nil
        foodCell = nil
        scoreLabel = nil
        saveMessageLabel = nil
        isGameOver = false
        isPausedGame = false
        isPaused = false
        if view != nil { setupSaveMessageLabel() }
    }

    private func shareScore() {
        let activityViewController = UIActivityViewController(
            activityItems: ["I scored \(score) points in slyme! play now: https://apps.apple.com/us/app/slyme/id6739715471"],
            applicationActivities: nil
        )
        if let vc = view?.window?.rootViewController {
            activityViewController.popoverPresentationController?.sourceView = view
            activityViewController.popoverPresentationController?.sourceRect = CGRect(x: (view?.bounds.midX ?? 0), y: (view?.bounds.midY ?? 0), width: 1, height: 1)
            vc.present(activityViewController, animated: true, completion: nil)
        }
    }

    private func goToMainMenu() {
        guard let view = self.view else { return }
        let mainMenuScene = MainMenu(size: view.bounds.size)
        mainMenuScene.scaleMode = .resizeFill
        view.presentScene(mainMenuScene, transition: SKTransition.fade(withDuration: 0.5))
    }

    private func updateSnakeDisplay() {
        children.filter { $0.name == "snakeSegment" }.forEach { $0.removeFromParent() }
        for (index, currentPosition) in snake.enumerated() {
            let previousPosition = index > 0 ? snake[index - 1] : nil
            let nextPosition = index < snake.count - 1 ? snake[index + 1] : nil
            let partType: SnakePartType = index == 0 ? .head : (index == snake.count - 1 ? .tail : .body)
            let textureName = partType.getTextureName(
                previousPosition: previousPosition,
                currentPosition: currentPosition,
                nextPosition: nextPosition,
                moveDirection: moveDirection
            )
            let node = skin.makeSegment(textureName: textureName, isHead: index == 0,
                                        size: CGSize(width: cellSize, height: cellSize))
            node.position = point(for: currentPosition)
            node.name = "snakeSegment"
            addChild(node)
        }
    }

    // MARK: - Save / restore

    public func saveGameState() {
        guard !isGameOver, !snake.isEmpty else { return }
        let save = GameSave(score: score, level: level, snake: snake, moveDirection: moveDirection,
                            elapsedTime: elapsedTime, skinID: skin.id, mapID: map.id,
                            food: foodCell, columns: gridWidth, rows: gridHeight)
        UserDefaults.standard.set(save.encode(), forKey: GameSave.key)
    }

    /// Restore a saved run. Anything from an older version, a different grid,
    /// or out of bounds is discarded instead of risking a crash or a bad board.
    public func loadGameState() {
        guard let state = UserDefaults.standard.dictionary(forKey: GameSave.key) else { return }
        // Prefer the map/skin the run started on if still unlocked.
        if let id = state["map"] as? String, let saved = MapCatalog.map(id: id),
           EntitlementStore.shared.isUnlocked(mapID: id) {
            map = saved
        }
        if let id = state["skin"] as? String, let saved = SkinCatalog.skin(id: id),
           EntitlementStore.shared.isUnlocked(skinID: id) {
            skin = saved
        }
        guard let save = GameSave.decode(state, columns: gridWidth, rows: gridHeight,
                                         blocked: { x, y in isBlocked((x, y)) }) else {
            map = EntitlementStore.shared.selectedMap
            skin = EntitlementStore.shared.selectedSkin
            resetSavedGameState()
            return
        }
        snake = save.snake
        score = save.score
        level = save.level
        elapsedTime = save.elapsedTime
        startTime = 0
        moveDirection = save.moveDirection
        updateSpeedForLevel()
        if let f = save.food { placeFood(at: f) } else { spawnFood() }
        scoreLabel?.text = "Score: \(score) | Level: \(level)"
        clockLabel?.text = format(timeInterval: elapsedTime)
        drawMap()
        updateSnakeDisplay()
    }

    private func resetSavedGameState() {
        UserDefaults.standard.removeObject(forKey: GameSave.key)
    }

    /// Internal (not private) so TwoPlayerScene reuses the same texture picking.
    enum SnakePartType {
        case head
        case body
        case tail

        func getTextureName(previousPosition: (Int, Int)?,
                            currentPosition: (Int, Int),
                            nextPosition: (Int, Int)?,
                            moveDirection: CGVector) -> String {
            switch self {
            case .head:
                // For single segment snake (head only), use moveDirection
                if nextPosition == nil {
                    if moveDirection.dx > 0 { return "head_right" }
                    if moveDirection.dx < 0 { return "head_left" }
                    if moveDirection.dy > 0 { return "head_up" }
                    if moveDirection.dy < 0 { return "head_down" }
                    return "head_right" // default direction
                }
                
                // Existing logic for when there are multiple segments
                guard let next = nextPosition else { return "head_right" }
                let dx = currentPosition.0 - next.0
                let dy = currentPosition.1 - next.1
                
                if dx > 0 { return "head_right" }
                if dx < 0 { return "head_left" }
                if dy > 0 { return "head_up" }
                return "head_down"

            case .tail:
                guard let prev = previousPosition else { return "tail_left" }
                let dx = prev.0 - currentPosition.0
                let dy = prev.1 - currentPosition.1
                if dx > 0 { return "tail_left" }
                if dx < 0 { return "tail_right" }
                if dy > 0 { return "tail_down" }
                //print("tookthatthangupshootymake it roll")
                return "tail_up"

            case .body:
                guard let prev = previousPosition, let next = nextPosition else {
                    return "body_horizontal"
                }

                let isVertical = prev.0 == next.0
                let isHorizontal = prev.1 == next.1

                if isVertical { return "body_vertical" }
                if isHorizontal { return "body_horizontal" }

                // Handle corners
                let dx1 = currentPosition.0 - prev.0
                let dy1 = currentPosition.1 - prev.1
                let dx2 = next.0 - currentPosition.0
                let dy2 = next.1 - currentPosition.1

                switch (dx1, dy1, dx2, dy2) {
                case (1, 0, 0, 1), (0, -1, -1, 0):
                    return "body_topleft"
                case (-1, 0, 0, 1), (0, -1, 1, 0):
                    return "body_topright"
                case (1, 0, 0, -1), (0, 1, -1, 0):
                    return "body_bottomleft"
                case (-1, 0, 0, -1), (0, 1, 1, 0):
                    return "body_bottomright"
                default:
                    return "body_vertical"
                }
            }
        }
    }
}
