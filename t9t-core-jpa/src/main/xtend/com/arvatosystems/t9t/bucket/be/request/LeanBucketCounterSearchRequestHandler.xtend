/*
 * Copyright (c) 2012 - 2018 Arvato Systems GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package com.arvatosystems.t9t.bucket.be.request

import com.arvatosystems.t9t.base.jpa.impl.AbstractLeanSearchRequestHandler
import com.arvatosystems.t9t.base.search.Description
import de.jpaw.dp.Jdp
import com.arvatosystems.t9t.bucket.request.LeanBucketCounterSearchRequest
import com.arvatosystems.t9t.bucket.jpa.entities.BucketCounterEntity
import com.arvatosystems.t9t.bucket.jpa.persistence.IBucketCounterEntityResolver

class LeanBucketCounterSearchRequestHandler extends AbstractLeanSearchRequestHandler<LeanBucketCounterSearchRequest, BucketCounterEntity> {

    public new() {
        super(Jdp.getRequired(IBucketCounterEntityResolver),
            [ return new Description(null, qualifier, qualifier, false, false) ]
        )
    }
}
