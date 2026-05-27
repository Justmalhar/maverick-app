// client/Sources/App/SplashScreenView.swift
import SwiftUI

struct SplashScreenView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "star.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .foregroundStyle(.white)

                Text("Maverick")
                    .font(.custom("Helvetica Neue", size: 34))
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .kerning(3)
            }
        }
    }
}
