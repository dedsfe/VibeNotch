//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import Network

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @EnvironmentObject var agentWrapper: AIAgentWrapper
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
        .onChange(of: agentWrapper.sessions.count) { _, count in
            if count > 0 {
                coordinator.currentView = .terminal
                vm.open()
            } else {
                vm.close()
            }
        }
        .onChange(of: agentWrapper.collapseTick) { _, _ in
            // As sessoes terminadas continuam na lista, entao quem manda
            // recolher e o CLI avisando que acabou.
            if agentWrapper.waitingCount == 0 { vm.close() }
        }
        .onChange(of: agentWrapper.waitingCount) { _, waiting in
            // Um novo pedido de aprovacao reabre a ilha mesmo se ela ja estava aberta.
            if waiting > 0 {
                coordinator.currentView = .terminal
                vm.open()
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                            }

                            Rectangle()
                                .fill(.black)
                                .frame(width: vm.closedNotchSize.width + 10)

                            HStack {
                                BoringBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    case .terminal:
                        if !agentWrapper.sessions.isEmpty {
                            AISessionListView(agentWrapper: agentWrapper)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text("No active CLI requests")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.gray)
                                Text("Background agents are sleeping.")
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.gray.opacity(0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                        }
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] && vm.notchState == .closed {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    // Enquanto algum CLI espera clique, a ilha nao foge do mouse.
                    if self.agentWrapper.waitingCount > 0 { return }

                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
import Foundation
import Combine

class AIAgentWrapper: ObservableObject {
    @Published var isRequestingPermission: Bool = false
    @Published var permissionPrompt: String = ""

    @Published var isShowingMessage: Bool = false
    @Published var sourceName: String = "Claude Code"

    private static let sourceNames: [String: String] = [
        "claude": "Claude Code",
        "gemini": "Gemini",
        "antigravity": "Antigravity",
        "codex": "Codex",
    ]

    /// Uma sessao por CLI aberto. A ilha mostra essa lista.
    @Published var sessions: [AISession] = []
    /// Qual sessao esta em foco no painel (a que mostra mensagem e botoes).
    @Published var focusedSessionID: String?
    /// Sobe quando um CLI pede pra recolher a ilha. As sessoes ficam na
    /// lista depois de terminarem, entao sessions.count nao serve mais
    /// como sinal de "pode fechar".
    @Published var collapseTick: Int = 0

    /// Utilizacao (0-100) por provedor ("claude", "codex", ...), vinda do
    /// hook junto com os eventos. Cada provedor com fonte de quota ganha
    /// sua propria capsula no header.
    @Published var usageByProvider: [String: AIUsage] = [:]

    /// Quantas conversas terminadas ficam guardadas pra voltar nelas.
    private let limiteDeSessoes = 5

    var focusedSession: AISession? {
        sessions.first { $0.id == focusedSessionID }
    }

    var waitingCount: Int {
        sessions.filter { $0.isWaiting }.count
    }

    private var listener: NWListener?
    private var activeConnection: NWConnection?
    /// Socket de quem esta esperando resposta, por sessao. Sem isso, dois CLIs
    /// pedindo permissao ao mesmo tempo fariam o clique ir pro socket errado.
    private var pendingConnections: [String: NWConnection] = [:]

    func focus(on sessionID: String) {
        focusedSessionID = sessionID
    }

    /// Traz pra frente a aba do terminal onde essa sessao esta rodando.
    /// Casa pelo tty, que e o unico id estavel: titulo de aba muda sozinho.
    func jumpToTerminal(sessionID: String) {
        guard let sessao = sessions.first(where: { $0.id == sessionID }),
              !sessao.tty.isEmpty else { return }

        let alvo = sessao.term == "iTerm.app" ? "iTerm" : "Terminal"
        let script: String

        if alvo == "iTerm" {
            script = """
            tell application "iTerm"
                repeat with j in windows
                    repeat with a in tabs of j
                        repeat with s in sessions of a
                            if tty of s is "\(sessao.tty)" then
                                select j
                                select a
                                select s
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        } else {
            script = """
            tell application "Terminal"
                repeat with j in windows
                    repeat with a in tabs of j
                        if tty of a is "\(sessao.tty)" then
                            set selected of a to true
                            set frontmost of j to true
                            activate
                            return
                        end if
                    end repeat
                end repeat
            end tell
            """
        }

        // AppleScript pode travar alguns segundos esperando o app responder.
        DispatchQueue.global(qos: .userInitiated).async {
            var erro: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&erro)
            if let erro { print("Pulo pro terminal falhou: \(erro)") }
        }
    }

    func startAgent() {
        do {
            let port = NWEndpoint.Port(rawValue: 8123)!
            listener = try NWListener(using: .tcp, on: port)
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.start(queue: .main)
            print("AI Notch Server listening on port 8123")
        } catch {
            print("Failed to start server: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        receiveNextMessage(on: connection)
    }
    
    private func receiveNextMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                print("Received from CLI wrapper: \(message)")
                
                // Using JSON for the protocol
                // Ex: {"type":"prompt","message":"Do you want to allow this command?"}
                if let jsonData = message.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any],
                   let type = dict["type"] as? String {

                    let rawSource = dict["source"] as? String ?? "claude"

                    // Medidor de uso pega carona em qualquer evento; cada
                    // provedor guarda o seu.
                    if let uso = dict["usage"] as? [String: Any] {
                        let cinco = uso["five"] as? Double ?? -1
                        let sete = uso["seven"] as? Double ?? -1
                        DispatchQueue.main.async {
                            self?.usageByProvider[rawSource] = AIUsage(five: cinco, seven: sete)
                        }
                    }
                    let displayName = Self.sourceNames[rawSource] ?? rawSource.capitalized
                    // Sem session id, cada CLI vira uma linha so (por origem).
                    let sessionID = (dict["session"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                        ?? "anon-\(rawSource)"
                    let project = dict["project"] as? String ?? ""

                    if type == "prompt", let promptText = dict["message"] as? String {
                        DispatchQueue.main.async {
                            self?.pendingConnections[sessionID] = connection
                            self?.upsert(
                                id: sessionID, source: rawSource, name: displayName,
                                project: project, state: .waiting, message: promptText,
                                rule: dict["rule"] as? String ?? "",
                                tty: dict["tty"] as? String ?? "",
                                term: dict["term"] as? String ?? ""
                            )
                            // Quem pede aprovacao rouba o foco: e o unico que trava o CLI.
                            self?.focusedSessionID = sessionID

                            self?.activeConnection = connection
                            self?.sourceName = displayName
                            self?.permissionPrompt = promptText
                            self?.isShowingMessage = false
                            self?.isRequestingPermission = true
                        }
                    } else if type == "message", let msgText = dict["message"] as? String {
                        let state = AISessionState.from(wire: dict["state"] as? String)
                        DispatchQueue.main.async {
                            self?.upsert(
                                id: sessionID, source: rawSource, name: displayName,
                                project: project, state: state, message: msgText,
                                title: dict["title"] as? String ?? "",
                                tty: dict["tty"] as? String ?? "",
                                term: dict["term"] as? String ?? ""
                            )
                            // Aviso passivo nao rouba o foco de quem esta travado esperando.
                            if self?.focusedSession?.isWaiting != true {
                                self?.focusedSessionID = sessionID
                            }

                            guard self?.isRequestingPermission != true else { return }
                            self?.activeConnection = connection
                            self?.sourceName = displayName
                            self?.permissionPrompt = msgText
                            self?.isShowingMessage = true
                        }
                    } else if type == "close" {
                        DispatchQueue.main.async {
                            self?.pendingConnections.removeValue(forKey: sessionID)

                            // A sessao NAO sai da lista: e clicando nela que
                            // se volta pro terminal daquela conversa. So perde
                            // o destaque de quem estava esperando resposta.
                            if let i = self?.sessions.firstIndex(where: { $0.id == sessionID }),
                               self?.sessions[i].isWaiting == true {
                                self?.sessions[i].state = .idle
                            }
                            self?.podarSessoes()

                            // So recolhe a ilha se ninguem mais precisa dela.
                            if self?.sessions.contains(where: { $0.isWaiting }) != true {
                                self?.activeConnection = nil
                                self?.isRequestingPermission = false
                                self?.isShowingMessage = false
                                self?.collapseTick += 1
                            }
                        }
                    }
                }
            }
            
            if isComplete || error != nil {
                // Connection closed or error
            } else {
                self?.receiveNextMessage(on: connection)
            }
        }
    }
    
    /// Cria ou atualiza a linha daquela sessao na lista.
    private func upsert(
        id: String, source: String, name: String,
        project: String, state: AISessionState, message: String,
        rule: String = "", title: String = "",
        tty: String = "", term: String = ""
    ) {
        if let i = sessions.firstIndex(where: { $0.id == id }) {
            sessions[i].source = source
            sessions[i].name = name
            sessions[i].state = state
            sessions[i].message = message
            sessions[i].rule = rule
            sessions[i].updatedAt = Date()
            if !project.isEmpty { sessions[i].project = project }
            // Pedido de permissao nao carrega titulo: nao apaga o que ja tem.
            if !title.isEmpty { sessions[i].title = title }
            if !tty.isEmpty { sessions[i].tty = tty }
            if !term.isEmpty { sessions[i].term = term }
        } else {
            // Mesma aba de terminal = mesma linha. Um restart ou /clear
            // troca o session_id, mas o tty fica -- sem isso cada sessao
            // nova viraria uma linha fantasma da mesma aba.
            if !tty.isEmpty {
                sessions.removeAll { $0.tty == tty && !$0.isWaiting }
            }
            sessions.append(AISession(
                id: id, source: source, name: name, project: project,
                title: title, tty: tty, term: term,
                state: state, message: message, rule: rule
            ))
        }
    }

    /// Guarda so as conversas mais recentes. Quem ainda espera resposta
    /// nunca e podado: perder o pedido travaria o CLI pra sempre.
    private func podarSessoes() {
        guard sessions.count > limiteDeSessoes else { return }

        let ordenadas = sessions.sorted { $0.updatedAt > $1.updatedAt }
        let manter = Set(
            ordenadas.prefix(limiteDeSessoes).map(\.id)
        ).union(sessions.filter(\.isWaiting).map(\.id))

        sessions.removeAll { !manter.contains($0.id) }
        if let atual = focusedSessionID, !manter.contains(atual) {
            focusedSessionID = sessions.first?.id
        }
    }

    func approve(sessionID: String) {
        respond("y\n", to: sessionID)
    }

    func deny(sessionID: String) {
        respond("n\n", to: sessionID)
    }

    /// Aprova e manda o hook gravar a regra em settings.local.json.
    func alwaysAllow(sessionID: String) {
        respond("a\n", to: sessionID)
    }

    // Compatibilidade: sem id, responde quem esta em foco.
    func approve() {
        guard let id = focusedSessionID else { return }
        approve(sessionID: id)
    }

    func deny() {
        guard let id = focusedSessionID else { return }
        deny(sessionID: id)
    }

    /// Responde o CLI daquela sessao — e so daquela.
    private func respond(_ response: String, to sessionID: String) {
        if let i = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[i].state = .working
            sessions[i].message = ""
            sessions[i].rule = ""
        }

        // Se ainda tem outro CLI travado, a ilha continua nele.
        if let next = sessions.first(where: { $0.isWaiting }) {
            focusedSessionID = next.id
            permissionPrompt = next.message
            sourceName = next.name
            isRequestingPermission = true
        } else {
            isRequestingPermission = false
            permissionPrompt = ""
        }

        guard let connection = pendingConnections.removeValue(forKey: sessionID) else { return }
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("Failed to send response: \(error)")
            }
            // Close the connection after responding to the wrapper
            connection.cancel()
        }))
        if connection === activeConnection { activeConnection = nil }
    }
}
import SwiftUI

struct AITerminalView: View {
    @ObservedObject var agentWrapper: AIAgentWrapper
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(agentWrapper.isRequestingPermission ? Color.orange : Color.blue)
                    .frame(width: 8, height: 8)
                Text(agentWrapper.isRequestingPermission ? "Permission Request" : "Message")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Tool and Context
            HStack {
                Text(agentWrapper.isRequestingPermission ? "⚠️" : "💬")
                Text(agentWrapper.sourceName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // The Prompt itself
            Text(agentWrapper.permissionPrompt.isEmpty ? "..." : agentWrapper.permissionPrompt)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.8))
                .lineLimit(4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            
            // Buttons
            if agentWrapper.isRequestingPermission {
                HStack(spacing: 12) {
                    Button(action: {
                        agentWrapper.deny()
                    }) {
                        Text("Deny")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button(action: {
                        agentWrapper.approve()
                    }) {
                        Text("Allow")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            } else {
                Spacer().frame(height: 16)
            }
        }
        .frame(width: 320)
        .background(Color.black)
    }
}
import SwiftUI

/// Estado de uma sessao de CLI vista pela ilha.
enum AISessionState: String {
    case working
    case waiting   // pediu permissao e esta parado esperando o clique
    case idle
    case error
    case offline

    /// Nomes que os hooks mandam em "state" (ver ~/AINotch/hooks/ainotch-notify).
    static func from(wire: String?) -> AISessionState {
        switch wire {
        case "pedido": return .waiting
        case "erro": return .error
        case "offline": return .offline
        case "working": return .working
        default: return .idle
        }
    }

    var color: Color {
        switch self {
        case .working: return .blue
        case .waiting: return .orange
        case .idle: return .green
        case .error: return .red
        case .offline: return .gray
        }
    }

    var label: String {
        switch self {
        case .working: return "trabalhando"
        case .waiting: return "quer aprovação"
        case .idle: return "livre"
        case .error: return "erro"
        case .offline: return "encerrada"
        }
    }
}

/// Uma sessao de CLI (um Claude, um Codex, um Gemini...) rastreada pela ilha.
struct AISession: Identifiable {
    let id: String
    var source: String       // claude / codex / gemini / antigravity
    var name: String         // nome bonito pra tela
    var project: String      // pasta onde ele esta rodando
    /// Assunto da conversa, vindo do CLI (o mesmo titulo da aba do
    /// terminal). Sem ele a linha cai de volta pro nome da pasta.
    var title: String = ""
    /// Terminal onde o CLI roda (ex: "/dev/ttys000" + "Apple_Terminal"),
    /// pra ilha conseguir trazer a aba certa pra frente.
    var tty: String = ""
    var term: String = ""
    var state: AISessionState
    var message: String
    /// Regra que o botao "Sempre" gravaria (ex: "Bash(git status:*)").
    /// Vazia = o hook nao conseguiu estreitar o suficiente, esconde o botao.
    var rule: String = ""
    var updatedAt: Date = Date()

    var isWaiting: Bool { state == .waiting }
}

/// Utilizacao 5h/7d de um provedor. -1 = sem dado naquela janela.
struct AIUsage: Equatable {
    var five: Double
    var seven: Double
}

/// "5h 12%" com cor subindo junto com o consumo.
struct UsageBadge: View {
    let label: String
    let value: Double  // 0-100; negativo = sem dado

    private var cor: Color {
        if value >= 80 { return .red }
        if value >= 50 { return .orange }
        return .green
    }

    var body: some View {
        if value >= 0 {
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                Text("\(Int(value.rounded()))%")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(cor.opacity(0.95))
            }
            .fixedSize()
        }
    }
}

/// Linha da lista: bolinha de estado + quem e + onde esta.
struct AISessionRow: View {
    let session: AISession
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(session.state.color)
                .frame(width: 6, height: 6)

            Text(session.name)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .fixedSize()

            // Assunto da conversa diz mais que a pasta; a pasta so entra
            // quando o CLI ainda nao nomeou o papo.
            let assunto = session.title.isEmpty ? session.project : session.title
            if !assunto.isEmpty {
                Text(assunto)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Text(session.state.label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(session.state.color.opacity(0.95))
                .fixedSize()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    session.isWaiting ? session.state.color.opacity(0.45) : .clear,
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
    }
}

/// Painel principal: lista todas as sessoes e, quando alguma pede permissao,
/// mostra o pedido dela com Allow/Deny.
struct AISessionListView: View {
    @ObservedObject var agentWrapper: AIAgentWrapper

    /// A ilha tem 190px fixos: a lista rola, o pedido em foco fica sempre visivel.
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text("Agentes")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))

                    Spacer(minLength: 4)

                    if agentWrapper.waitingCount > 0 {
                        Text("\(agentWrapper.waitingCount) esperando")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.orange)
                            .fixedSize()
                    }

                    // O medidor de uso nao mora mais aqui: espremia o
                    // titulo. Ele aparece no painel da sessao em foco.
                }

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 3) {
                        // Quem espera resposta em cima; o resto por ultimo
                        // visto. O "agrupamento" por CLI acontece sozinho.
                        let ordenadas = agentWrapper.sessions.sorted {
                            if $0.isWaiting != $1.isWaiting { return $0.isWaiting }
                            return $0.updatedAt > $1.updatedAt
                        }
                        ForEach(ordenadas) { session in
                            AISessionRow(
                                session: session,
                                isSelected: session.id == agentWrapper.focusedSession?.id
                            )
                            // Duplo clique ANTES do simples: SwiftUI testa na
                            // ordem e o de 2 toques precisa ganhar a disputa.
                            .onTapGesture(count: 2) {
                                agentWrapper.focus(on: session.id)
                                agentWrapper.jumpToTerminal(sessionID: session.id)
                            }
                            .onTapGesture {
                                // 1 clique so poe em foco (mostra painel e
                                // quota); quem quer o terminal clica 2x.
                                agentWrapper.focus(on: session.id)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Painel do lado: pedido esperando resposta ou o fecho de quem
            // acabou. "Livre" sozinho nao diz nada -- a ultima frase diz.
            if let focused = agentWrapper.focusedSession, !focused.message.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) {
                        Text(focused.isWaiting ? "⚠️" : "✅").font(.system(size: 10))
                        Text(focused.title.isEmpty ? focused.name : focused.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)

                        // Quota da conta DESSA sessao, so quando ela esta
                        // em foco -- no header espremia o titulo da lista.
                        if let uso = agentWrapper.usageByProvider[focused.source] {
                            HStack(spacing: 4) {
                                UsageBadge(label: "5h", value: uso.five)
                                Text("·")
                                    .font(.system(size: 9))
                                    .foregroundColor(.white.opacity(0.2))
                                UsageBadge(label: "7d", value: uso.seven)
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .fixedSize()
                        }
                    }

                    Text(focused.message)
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(focused.isWaiting ? 3 : 5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)

                    Spacer(minLength: 0)

                    // Quem so terminou nao tem o que responder: sem botoes.
                    if focused.isWaiting {
                        HStack(spacing: 6) {
                            Button(action: { agentWrapper.deny(sessionID: focused.id) }) {
                                Text("Deny")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Color.white.opacity(0.12))
                                    .cornerRadius(7)
                            }
                            .buttonStyle(PlainButtonStyle())

                            // So aparece quando o hook conseguiu gerar uma regra
                            // estreita: sem isso, um clique liberaria demais.
                            if !focused.rule.isEmpty {
                                Button(action: { agentWrapper.alwaysAllow(sessionID: focused.id) }) {
                                    Text("Sempre")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 7)
                                        .background(Color.orange.opacity(0.35))
                                        .cornerRadius(7)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Libera \(focused.rule) pra sempre em settings.local.json")
                            }

                            Button(action: { agentWrapper.approve(sessionID: focused.id) }) {
                                Text("Allow")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Color.white)
                                    .cornerRadius(7)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        // Mostra exatamente o que o "Sempre" vai gravar.
                        if !focused.rule.isEmpty {
                            Text(focused.rule)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.8))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(width: 250)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
