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

    ///MARK: create skins eventually
    private var snake: [(Int, Int)] = []
    private var food: SKSpriteNode?
    private var foodCell: (Int, Int)?
    private var moveDirection: CGVector = CGVector(dx: 1, dy: 0)
    private var nextMoveTime: TimeInterval = 0
    private var moveSpeed: TimeInterval = 0.1
    private var score: Int = 0
    private var scoreLabel: SKLabelNode?

    private var saveMessageLabel: SKLabelNode?

    private var level: Int = 1
    private var baseSpeed: TimeInterval = 0.1
    private let speedIncreaseFactor: Double = 0.85

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator()

    private var pauseButton: SKSpriteNode?
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
        updateSnakeDisplay()
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

        // Same start cell as before (60% across, 70% up), now in grid units.
        snake.insert((Int(Double(gridWidth) * 0.6), Int(Double(gridHeight) * 0.7)), at: 0)
        spawnFood()
    }

    /// Place food on a random free cell (never on the snake).
    private func spawnFood() {
        food?.removeFromParent()
        let occupied = Set(snake.map { $0.0 * 10_000 + $0.1 })
        var free: [(Int, Int)] = []
        free.reserveCapacity(gridWidth * gridHeight)
        for x in 0..<gridWidth {
            for y in 0..<gridHeight where !occupied.contains(x * 10_000 + y) {
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

    private func makePauseButton(imageNamed name: String) {
        let previous = pauseButton?.position
        pauseButton?.removeFromParent()
        let button = SKSpriteNode(imageNamed: name)
        button.position = previous ?? CGPoint(x: hudRect.maxX - 36, y: hudRect.maxY - 36)
        button.name = "pauseButton"
        button.size = CGSize(width: 40, height: 40)
        button.zPosition = 10
        addChild(button)
        pauseButton = button
    }

    private func setupPauseButton() { makePauseButton(imageNamed: "pause") }

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
        makePauseButton(imageNamed: "play")

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
        makePauseButton(imageNamed: "pause")
        isPausedGame = false
        self.isPaused = false
        startTime = 0 // re-anchor the clock so paused time isn't counted
        childNode(withName: "pausedLabel")?.removeFromParent()
        childNode(withName: "quitLabel")?.removeFromParent()
        childNode(withName: "saveGameButton")?.removeFromParent()
    }

    override func update(_ currentTime: TimeInterval) {
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
        let newHead = (
            (head.0 + Int(moveDirection.dx) + gridWidth) % gridWidth,
            (head.1 + Int(moveDirection.dy) + gridHeight) % gridHeight
        )

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
        return snake.dropFirst().contains { $0 == head }
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
            let node = SKSpriteNode(texture: SKTexture(imageNamed: textureName),
                                    size: CGSize(width: cellSize, height: cellSize))
            node.position = point(for: currentPosition)
            node.name = "snakeSegment"
            addChild(node)
        }
    }

    // MARK: - Save / restore

    public func saveGameState() {
        guard !isGameOver, !snake.isEmpty else { return }
        var gameState: [String: Any] = [
            "version": GameScene.saveVersion,
            "columns": gridWidth,
            "rows": gridHeight,
            "score": score,
            "level": level,
            "snake": snake.map { ["x": $0.0, "y": $0.1] },
            "moveDirection": ["dx": Double(moveDirection.dx), "dy": Double(moveDirection.dy)],
            "elapsedTime": elapsedTime
        ]
        if let f = foodCell { gameState["food"] = ["x": f.0, "y": f.1] }
        UserDefaults.standard.set(gameState, forKey: "savedGameState")
    }

    /// Restore a saved run. Anything from an older version, a different grid,
    /// or out of bounds is discarded instead of risking a crash or a bad board.
    public func loadGameState() {
        guard let state = UserDefaults.standard.dictionary(forKey: "savedGameState") else { return }
        guard state["version"] as? Int == GameScene.saveVersion,
              state["columns"] as? Int == gridWidth,
              state["rows"] as? Int == gridHeight,
              let raw = state["snake"] as? [[String: Int]], !raw.isEmpty else {
            resetSavedGameState()
            return
        }
        let cells = raw.compactMap { d -> (Int, Int)? in
            guard let x = d["x"], let y = d["y"] else { return nil }
            return (x, y)
        }
        let inBounds = cells.allSatisfy { (0..<gridWidth).contains($0.0) && (0..<gridHeight).contains($0.1) }
        let unique = Set(cells.map { $0.0 * 10_000 + $0.1 }).count == cells.count
        guard cells.count == raw.count, inBounds, unique else {
            resetSavedGameState()
            return
        }

        snake = cells
        score = max(0, state["score"] as? Int ?? 0)
        level = max(1, state["level"] as? Int ?? 1)
        elapsedTime = max(0, state["elapsedTime"] as? TimeInterval ?? 0)
        startTime = 0
        updateSpeedForLevel()
        if let d = state["moveDirection"] as? [String: Double],
           let dx = d["dx"], let dy = d["dy"], abs(dx) + abs(dy) == 1 {
            moveDirection = CGVector(dx: dx, dy: dy)
        }
        if let f = state["food"] as? [String: Int], let x = f["x"], let y = f["y"],
           (0..<gridWidth).contains(x), (0..<gridHeight).contains(y),
           !snake.contains(where: { $0 == (x, y) }) {
            placeFood(at: (x, y))
        } else {
            spawnFood()
        }
        scoreLabel?.text = "Score: \(score) | Level: \(level)"
        clockLabel?.text = format(timeInterval: elapsedTime)
        updateSnakeDisplay()
    }

    private func resetSavedGameState() {
        UserDefaults.standard.removeObject(forKey: "savedGameState")
    }

    private enum SnakePartType {
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
                    print("1")
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

                    print("this")
                    return "body_topleft"
                case (-1, 0, 0, 1), (0, -1, 1, 0):
                    print("that")
                    return "body_topright"
                case (1, 0, 0, -1), (0, 1, -1, 0):
                    print("typeshit")
                    return "body_bottomleft"
                case (-1, 0, 0, -1), (0, 1, 1, 0):
                    print("umm")
                    return "body_bottomright"
                default:
                    print("we got here")
                    return "body_vertical"
                }
            }
        }
    }
}
