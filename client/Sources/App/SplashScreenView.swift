// client/Sources/App/SplashScreenView.swift
import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image("MaverickLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 140, height: 140)

                Text("Maverick")
                    .font(.custom("Helvetica Neue", size: 34))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .kerning(3)
            }
        }
    }
}
