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
package com.arvatosystems.t9t.in.be.impl

import com.arvatosystems.t9t.base.T9tException
import com.arvatosystems.t9t.base.api.RequestParameters
import com.arvatosystems.t9t.base.api.ServiceResponse
import com.arvatosystems.t9t.base.auth.ApiKeyAuthentication
import com.arvatosystems.t9t.base.crud.CrudSurrogateKeyResponse
import com.arvatosystems.t9t.base.entities.FullTrackingWithVersion
import com.arvatosystems.t9t.base.request.ErrorRequest
import com.arvatosystems.t9t.base.types.SessionParameters
import com.arvatosystems.t9t.in.services.IInputDataTransformer
import com.arvatosystems.t9t.in.services.IInputFormatConverter
import com.arvatosystems.t9t.in.services.IInputSession
import com.arvatosystems.t9t.io.DataSinkDTO
import com.arvatosystems.t9t.io.DataSinkKey
import com.arvatosystems.t9t.io.DataSinkRef
import com.arvatosystems.t9t.io.SinkDTO
import com.arvatosystems.t9t.io.request.DataSinkCrudRequest
import com.arvatosystems.t9t.io.request.StoreSinkRequest
import com.arvatosystems.t9t.server.services.IStatefulServiceSession
import de.jpaw.annotations.AddLogger
import de.jpaw.bonaparte.core.BonaPortable
import de.jpaw.bonaparte.core.BonaPortableClass
import de.jpaw.bonaparte.core.BonaPortableFactory
import de.jpaw.bonaparte.pojos.api.OperationType
import de.jpaw.bonaparte.pojos.api.media.MediaType
import de.jpaw.dp.Dependent
import de.jpaw.dp.Inject
import de.jpaw.dp.Jdp
import de.jpaw.util.ApplicationException
import java.io.InputStream
import java.util.HashMap
import java.util.Map
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import org.joda.time.Instant
import com.arvatosystems.t9t.io.request.CheckSinkFilenameUsedRequest
import com.arvatosystems.t9t.io.request.CheckSinkFilenameUsedResponse

// this class operates outside of a RequestContext!
@AddLogger
@Dependent
class InputSession implements IInputSession {
    @Inject IStatefulServiceSession session // holds the backend connection
    protected final AtomicInteger numSource = new AtomicInteger // unmapped records
    protected final AtomicInteger numProcessed = new AtomicInteger // mapped records
    protected final AtomicInteger numError = new AtomicInteger // errors
    protected final Instant start = new Instant(System.currentTimeMillis)
    protected final SinkDTO sinkDTO = new SinkDTO
    protected DataSinkDTO dataSinkCfg
    protected BonaPortableClass<?> baseBClass
    protected IInputDataTransformer<BonaPortable> inputTransformer;
    protected IInputFormatConverter inputFormatConverter
    protected final Map<String, Object> headerData = new HashMap<String, Object>();
    protected String sourceReference = null;
    protected boolean isDuplicateImport = false;

    override open(String dataSourceId, UUID apiKey, String sourceURI, Map<String, Object> params) {
        LOGGER.info("Opening input session for dataSource ID {}, source URI {}", dataSourceId, sourceURI)

        // open a session
        sourceReference = "DS=" + dataSourceId + ", filename=" + (sourceURI ?: "-")
        val sessionParameters = new SessionParameters => [
            dataUri = sourceURI
        ]
        session.open(sessionParameters, new ApiKeyAuthentication(apiKey))

        val dataSinkReadRq = new DataSinkCrudRequest => [
            crud = OperationType.READ
            naturalKey = new DataSinkKey(dataSourceId)
        ]
        val resp = session.execute(dataSinkReadRq)
        if (resp.returnCode == 0 && resp instanceof CrudSurrogateKeyResponse) {
            dataSinkCfg = (resp as CrudSurrogateKeyResponse<DataSinkDTO, FullTrackingWithVersion>).data
        } else {
            throw new T9tException(T9tException.RECORD_DOES_NOT_EXIST, "DataSink " + dataSourceId)
        }

        if (Boolean.TRUE.equals(dataSinkCfg.checkDuplicateFilename)) {
            val checkResponse = session.execute(new CheckSinkFilenameUsedRequest => [
                                                  fileOrQueueName = sourceURI
                                                ]) as CheckSinkFilenameUsedResponse

            if (checkResponse.isUsed) {
                isDuplicateImport = true
                session.execute(new ErrorRequest => [
                    returnCode      = T9tException.IOF_DUPLICATE
                    errorDetails    = "Duplicate import file " + sourceURI + " for data sink " + dataSinkCfg.dataSinkId
                ])
            }
        }

        if (dataSinkCfg.baseClassPqon !== null) {
            baseBClass = BonaPortableFactory.getBClassForPqon(dataSinkCfg.baseClassPqon)
        }

        val formatName = if (dataSinkCfg.commFormatType.baseEnum != MediaType.USER_DEFINED)
            dataSinkCfg.commFormatType.name
        else
            dataSinkCfg.commFormatName
        if (formatName !== null) {
            inputFormatConverter = Jdp.getRequired(IInputFormatConverter, formatName)
        } else {
            throw new T9tException(T9tException.INVALID_CONFIGURATION, "Input format Converter has not been defined for camelRoute "+ dataSinkCfg.camelRoute)
        }
        if (inputFormatConverter !== null) {
            inputFormatConverter.open(this, dataSinkCfg, session, params, baseBClass)
        }
        if (dataSinkCfg.preTransformerName !== null) {
            inputTransformer = Jdp.getRequired(IInputDataTransformer, dataSinkCfg.preTransformerName)
        } else {
            inputTransformer = new IdentityTransformer()
        }
        inputTransformer.open(this, dataSinkCfg, session, params, baseBClass)

        sinkDTO.plannedRunDate  = start
        sinkDTO.commTargetChannelType = dataSinkCfg.commTargetChannelType
        sinkDTO.commFormatType  = dataSinkCfg.commFormatType
        sinkDTO.isInput         = Boolean.TRUE
        sinkDTO.category        = dataSinkCfg.category
        sinkDTO.fileOrQueueName = sourceURI
        sinkDTO.dataSinkRef     = new DataSinkRef(dataSinkCfg.objectRef)
        return dataSinkCfg
    }

    override String getSourceURI() {
        return sinkDTO.fileOrQueueName
    }

    override getTenantId() {
        return session?.tenantId
    }

    override void process(InputStream is) {
        inputFormatConverter.process(is)
    }

    // log according to configured severity and return an error request
    // this is called if an exception occurs during construction of either the DTO or the request
    def protected conditionalLog(String where, int recordNo, Exception e) {
        val errorCode = if (e instanceof ApplicationException) e.errorCode else T9tException.GENERAL_EXCEPTION
        val details = '''«where»: «sourceReference», record «recordNo»: «e.class.simpleName»: «e.message»'''
        LOGGER.error(details, e)
        return new ErrorRequest(errorCode, details, null)
    }

    override process(BonaPortable dto) {
        val recordNo = numSource.incrementAndGet

        // Fast fail in case of duplicates
        if (isDuplicateImport) {
            numError.incrementAndGet
            return
        }

        var RequestParameters rp = null

        // validate the first step's output
        try {
            dto.validate  // validate that the parser created a valid DTO

            // ok, DTO is good...
            try {
                rp = inputTransformer.transform(dto)
            } catch (Exception e) {
                // in case of an exception during conversion, send an error request
                rp = conditionalLog("Transform", recordNo, e)
            }
        } catch (Exception e) {
            // in case of an exception during conversion, send an error request
            rp = conditionalLog("Parse", recordNo, e)
        }

        // now feed it into the backend (unless it has been buffered)...
        if (rp !== null) process(rp)
    }

    override ServiceResponse process(RequestParameters rp) {
        if (isDuplicateImport) {
            numError.incrementAndGet
            return new ServiceResponse => [
                returnCode      = T9tException.IOF_DUPLICATE
                errorDetails    = "Duplicate import file " + sinkDTO.fileOrQueueName + " for data sink " + dataSinkCfg.dataSinkId
            ]
        }

        numProcessed.incrementAndGet
        val result = session.execute(rp)
        if (!ApplicationException.isOk(result.returnCode))
            numError.incrementAndGet
        return result
    }

    override close() {
        // flush any buffered data in the transformer
        val rp = inputTransformer.getPending()
        if (rp !== null) process(rp)
        // terminate the transformer. Flush it first
        inputTransformer.close
        inputFormatConverter.close

        // calculate statistics and write the sink record
        val end = System.currentTimeMillis
        sinkDTO.processingTime = (end - start.millis) as int
        sinkDTO.numberOfSourceRecords = numSource.get
        sinkDTO.numberOfMappedRecords = numProcessed.get
        sinkDTO.numberOfErrorRecords = numError.get
        session.execute(new StoreSinkRequest(sinkDTO))

        session.close
        LOGGER.info(
            "Imported dataSource {}, URI {}: {} records processed in {} ms ({} errors)",
            dataSinkCfg.dataSinkId,
            sinkDTO.fileOrQueueName,
            sinkDTO.numberOfSourceRecords,
            sinkDTO.processingTime,
            sinkDTO.numberOfErrorRecords
        )

        if (isDuplicateImport)
            throw new T9tException(T9tException.IOF_DUPLICATE, "Duplicate import file " + sourceURI + " for data sink " + dataSinkCfg.dataSinkId)
    }

    override getHeaderData(String name) {
        return headerData.get(name)
    }

    override setHeaderData(String name, Object value) {
        headerData.put(name, value)
    }
}
