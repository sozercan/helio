//
//  MasterButton.swift
//  Helio
//
//  Created by Igor Marcossi on 29/06/23.
//

import SwiftUI

enum MasterButtonMode {
  case soft
  case normal
  case subtle
}

enum ProportionalTypes {
  case no
  case circle
  case yes
}

struct MasterButton: View {
  var softDisabled = false
  var icon: String?
  var img: String?
  var label: String?
  var mode: MasterButtonMode = .normal
  var color: Color = .blue
  var textColor: Color = .white
  var textSize: CGFloat = 16
  var textWeight: Font.Weight = .semibold
  var textDesign: Font.Design = .rounded
  var height: CGFloat = 36
  var fullWidth: Bool = false
  var align: Alignment = .center
  var fullHeight: Bool = false
  var cornerRadius: CGFloat = 10
  var proportional: ProportionalTypes = .no
  var growAnchor: Alignment = .center
  var disabled = false
  var hoverWorkaround = false
  let action: () -> Void

  var body: some View {
    let btnCornerRadius = proportional == .circle ? height / 2 : cornerRadius
    let finalColor = color.opacity(mode == .normal ? 1 : mode == .subtle ? 0 : 0.2)
    let proportionalSize = proportional != .no ? height : nil
    HStack {
      if let img {
        Image(img)
          .resizable()
          .scaledToFit()
          .frame(height: textSize)
      }
      if let icon {
        Image(systemName: icon).contentTransition(.symbolEffect)
      }
      Group {
        if let label {
          Text(label).fixedSize(horizontal: true, vertical: false)
        }
      }
      .transition(.scaleAndBlur)
    }
    .fontSize(textSize, textWeight, design: textDesign)
    //            .padding(.vertical, padding)
    .padding(.horizontal, 10 * 1.5)
    .foregroundColor(textColor)
    .frame(maxWidth: fullWidth ? .infinity : nil, maxHeight: fullHeight ? .infinity : height, alignment: align)
    .frame(width: proportionalSize, height: fullHeight ? nil : height)
    .background(RR(btnCornerRadius, finalColor))
    .mask(RR(btnCornerRadius, .black))
    .contentShape(RoundedRectangle(cornerRadius: btnCornerRadius, style: .continuous))
    .highPriorityGesture(softDisabled ? nil : TapGesture().onEnded { action() })
    .disabled(disabled)
    .saturation(disabled ? 0 : 1)
    .opacity(disabled ? 0.65 : 1)
    .frame(maxWidth: fullWidth ? .infinity : nil, alignment: growAnchor)
  }
}
