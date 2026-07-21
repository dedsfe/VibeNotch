import SwiftUI

struct AIPermissionView: View {
    @ObservedObject var agentWrapper: AIAgentWrapper
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
                Text("Permission Request")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Tool and Context
            HStack {
                Text("⚠️")
                Text("Claude Code")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal, 16)
            
            // The Prompt itself
            Text(agentWrapper.permissionPrompt.isEmpty ? "Do you want to allow this action?" : agentWrapper.permissionPrompt)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)
                .padding(.horizontal, 16)
            
            // Buttons
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
        }
        .frame(width: 320)
        .background(Color.black)
    }
}
