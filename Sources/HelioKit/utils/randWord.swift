import Foundation

func randomWord(wordLength: Int = 6) -> String {
  let kCons = 1
  let kVows = 2

  var cons: [String] = [
    "b", "c", "d", "f", "g", "h", "j", "k", "l", "m",
    "n", "p", "r", "s", "t", "v", "w", "x", "z",
    "pt", "gl", "gr", "ch", "ph", "ps", "sh", "st", "th", "wh",
  ]

  let cons_cant_start: [String] = [
    "ck", "cm",
    "dr", "ds",
    "ft",
    "gh", "gn",
    "kr", "ks",
    "ls", "lt", "lr",
    "mp", "mt", "ms",
    "ng", "ns",
    "rd", "rg", "rs", "rt",
    "ss",
    "ts", "tch",
  ]

  let vows: [String] = [
    "a", "e", "i", "o", "u", "y",
    "ee", "oa", "oo",
  ]

  var current = (Int(arc4random_uniform(2)) == 1 ? kCons : kVows)

  var word = ""
  while word.count < wordLength {
    if word.count == 2 {
      cons = cons + cons_cant_start
    }

    var rnd = ""
    var index: Int
    if current == kCons {
      index = Int(arc4random_uniform(UInt32(cons.count)))
      rnd = cons[index]
    } else if current == kVows {
      index = Int(arc4random_uniform(UInt32(vows.count)))
      rnd = vows[index]
    }

    let tempWord = "\(word)\(rnd)"
    if tempWord.count <= wordLength {
      word = "\(word)\(rnd)"
      current = (current == kCons) ? kVows : kCons
    }
  }

  return word
}
