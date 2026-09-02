package com.wassalni.core.data.di

import com.wassalni.core.data.auth.AuthRepository
import com.wassalni.core.data.auth.ProfileRepository
import com.wassalni.core.data.auth.SupabaseAuthRepository
import com.wassalni.core.data.auth.SupabaseProfileRepository
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
abstract class RepositoryModule {

    @Binds
    @Singleton
    abstract fun bindAuthRepository(impl: SupabaseAuthRepository): AuthRepository

    @Binds
    @Singleton
    abstract fun bindProfileRepository(impl: SupabaseProfileRepository): ProfileRepository
}
