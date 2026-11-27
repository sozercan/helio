import MorphingStain from "./MorphingStain"

const BGDimmer = ({ dimBG }) => {
  return (
    <div className="helioBlurMask" style={{ opacity: dimBG ? 1 : 0 }} />
  )
}

export default BGDimmer




