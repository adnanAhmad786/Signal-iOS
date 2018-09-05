//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountManager: AccountManager {
        return AccountManager.shared
    }
    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }

        firstly {
            self.accountManager.getPreKeysCount()
        }.then(on: DispatchQueue.global()) { preKeysCount -> Promise<Void> in
            Logger.debug("preKeysCount: \(preKeysCount)")
            guard preKeysCount < kEphemeralPreKeysMinimumCount || self.primaryStorage.currentSignedPrekeyId() == nil else {
                Logger.debug("Available keys sufficient: \(preKeysCount)")
                return Promise(value: ())
            }

            let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
            let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = self.primaryStorage.generatePreKeyRecords()

            return self.accountManager.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords).then { () -> Void in
                signedPreKeyRecord.markAsAcceptedByService()
                self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
                self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
                self.primaryStorage.storePreKeyRecords(preKeyRecords)

                TSPreKeyManager.clearSignedPreKeyRecords()
            }
        }.then { () -> Void in
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
        }.retainUntilComplete()
    }
}
