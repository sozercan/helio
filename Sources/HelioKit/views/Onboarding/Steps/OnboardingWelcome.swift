//
//  OnboardingWelcome.swift
//  Helio
//
//  Created by Igor Marcossi on 01/08/23.
//

import SwiftUI

struct OnboardingWelcome: View {
  var nextStep: () -> Void
  @State var showMark = false
  @State var showHello = false
  @State var showAppName = false
  @State var showBtn = false
  @State var showText = false
  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 12) {
        if showMark {
          AppMark(size: 128)
            .transition(.scaleAndBlur)
        }

        VStack(spacing: -2) {
          if showHello {
            Text("Hello!")
              .foregroundColor(.primary.opacity(0.75))
              .fontSize(20, .medium)
              .transition(.scaleAndBlur)
          }

          if showAppName {
            (Text("I'm ").font(Font.system(size: 24, weight: .semibold)).foregroundColor(.primary.opacity(0.75)) + Text("Helio").font(Font.system(size: 34, weight: .bold)).foregroundColor(.yellow))
              .transition(.scaleAndBlur)
          }
        }

        if showText {
          Text("I'm a beautiful client (made with A BUNCH of love) for Reddit.")
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 300)
            .transition(.opacity)
        }
      }

      if showBtn {
        MasterButton(label: "👋 Hi, Helio!", colorHoverEffect: .animated, textSize: 18, height: 48, cornerRadius: 16, action: nextStep)
          .padding(.top, 16)
          .transition(.scaleAndBlur)
      }
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
    .onAppear {
      if !showMark {
        doThisAfter(0.5) {
          withAnimation(spring) { showMark = true }
          doThisAfter(0.85) {
            withAnimation(spring) { showHello = true }
            doThisAfter(1.25) {
              withAnimation(spring) { showAppName = true }
              doThisAfter(1.0) {
                withAnimation(spring) { showText = true }
                doThisAfter(1.25) {
                  withAnimation(spring) { showBtn = true }
                }
              }
            }
          }
        }
      }
    }
  }
}

struct OnboardingWelcomeWrapper: View {
  var nextStep: () -> Void

  var body: some View {
    VStack {
      OnboardingWelcome(nextStep: nextStep)
    }
  }
}

//
// struct OnboardingWelcome_Previews: PreviewProvider {
//  static var previews: some View {
//    OnboardingWelcome()
//  }
// }
