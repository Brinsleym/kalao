// Derived from Mornye (https://github.com/mornyeapp/Mornye), Copyright 2026 zarzet,
// LGPL-3.0-only. Modified for Kalao.
package com.brinsley.kalao

import com.brinsley.kalao.backend.CancellationDomain
import com.brinsley.kalao.backend.CancellationRegistry
import com.brinsley.kalao.backend.RequestLease

// Acquire before queuing on IO, so a following channel cancellation also
// reaches work that has not started.
internal object NativeDataJobs {
    private val registry = CancellationRegistry(CancellationDomain.DATA_JOB)
    private val active = mutableMapOf<String, MutableList<RequestLease>>()

    @Synchronized
    fun acquire(id: String): RequestLease {
        val lease = registry.acquire(id)
        active.getOrPut(id) { mutableListOf() }.add(lease)
        return lease
    }

    @Synchronized
    fun cancel(id: String) {
        // Jobs are acquired in channel order and must not retain pre-cancel sentinels.
        if (active[id]?.isNotEmpty() == true) registry.cancel(id)
    }

    @Synchronized
    fun release(id: String, lease: RequestLease) {
        val leases = active[id] ?: return
        val index = leases.indexOfFirst { it === lease }
        if (index < 0) return
        leases.removeAt(index)
        try {
            lease.release()
        } finally {
            try {
                lease.close()
            } finally {
                if (leases.isEmpty()) active.remove(id)
            }
        }
    }
}
