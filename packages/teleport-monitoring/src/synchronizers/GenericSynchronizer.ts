import { merge } from 'lodash'

import { BlockchainClient } from '../peripherals/blockchain'
import { SynchronizerStatusRepository } from '../peripherals/db/SynchronizerStatusRepository'
import { TxHandle } from '../peripherals/db/utils'
import { delay } from '../utils'

export interface SyncOptions {
  tipSyncDelay: number // ms
  saveDistanceFromTip: number
}

export const defaultSyncOptions: SyncOptions = {
  tipSyncDelay: 5_000,
  saveDistanceFromTip: 0,
}

export type SynchronizerState = 'stopped' | 'syncing' | 'synced'

export abstract class GenericSynchronizer {
  private readonly options: SyncOptions
  public readonly syncName: string

  constructor(
    private readonly blockchain: BlockchainClient,
    private readonly synchronizerStatusRepository: SynchronizerStatusRepository,
    public readonly domainName: string,
    public readonly startingBlock: number,
    public readonly blocksPerBatch: number,
    _options?: Partial<SyncOptions>,
  ) {
    this.syncName = this.constructor.name
    this.options = merge({}, defaultSyncOptions, _options)
  }

  private _state: SynchronizerState = 'stopped'
  get state(): SynchronizerState {
    return this._state
  }
  stop() {
    this._state = 'stopped'
  }
  private setSynced() {
    if (this.state === 'syncing') {
      this._state = 'synced'
    }
  }
  private setSyncing() {
    this._state = 'syncing'
  }

  async syncOnce(): Promise<void> {
    console.log('syncing once!')
    void this.run()
    while (this.state === 'syncing') {
      console.log('still syncing!')
      await delay(1000)
    }
    console.log('stopping!!')
    this.stop()
  }

  async run(): Promise<void> {
    this.setSyncing()
    const syncStatus = await this.synchronizerStatusRepository.findByName(this.syncName, this.domainName)
    let fromBlockNumber = syncStatus?.block ?? this.startingBlock // inclusive

    while (this.state !== 'stopped') {
      const currentBlock = (await this.blockchain.getLatestBlockNumber()) - this.options.saveDistanceFromTip
      const toBlockNumber = Math.min(fromBlockNumber + this.blocksPerBatch, currentBlock + 1) // exclusive

      if (fromBlockNumber !== toBlockNumber) {
        console.log(
          `[${this.syncName}] Syncing ${fromBlockNumber}...${toBlockNumber} (${(
            toBlockNumber - fromBlockNumber
          ).toLocaleString()} blocks)`,
        )

        await this.synchronizerStatusRepository.transaction(async (tx) => {
          await this.sync(tx, fromBlockNumber, toBlockNumber)
          await this.synchronizerStatusRepository.upsert(
            { domain: this.domainName, block: toBlockNumber, name: this.syncName },
            tx,
          )
        })
      }

      fromBlockNumber = toBlockNumber
      const onTip = toBlockNumber === currentBlock + 1
      if (onTip) {
        console.log('Syncing tip. Stalling....')
        this.setSynced()
        await delay(this.options.tipSyncDelay)
      }
    }
  }

  // from inclusive
  // to exclusive
  abstract sync(tx: TxHandle, from: number, to: number): Promise<void>
}
