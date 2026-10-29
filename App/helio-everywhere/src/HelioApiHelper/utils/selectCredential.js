function selectCredential(cred) {
   window.location.assign(`helioapp://?appID=${cred.appID}&appSecret=${cred.appSecret}`)
}

export default selectCredential
