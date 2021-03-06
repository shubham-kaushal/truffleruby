# frozen_string_literal: true

# Copyright (c) 2020 Oracle and/or its affiliates. All rights reserved. This
# code is released under a tri EPL/GPL/LGPL license. You can use it,
# redistribute it and/or modify it under the terms of the:
#
# Eclipse Public License version 2.0, or
# GNU General Public License version 2, or
# GNU Lesser General Public License version 2.1.

module Truffle
  module FeatureLoader

    DOT_DLEXT = ".#{Truffle::Platform::DLEXT}"

    # FeatureEntry => [*index_inside_$LOADED_FEATURES]
    @loaded_features_index = {}
    # A snapshot of $LOADED_FEATURES, to check if the @loaded_features_index cache is up to date.
    @loaded_features_copy = []

    def self.clear_cache
      @loaded_features_index.clear
      @loaded_features_copy.clear
    end

    class FeatureEntry
      attr_reader :feature, :ext, :feature_no_ext
      attr_accessor :part_of_index

      def initialize(feature)
        @part_of_index = false
        @ext = Truffle::FeatureLoader.extension(feature)
        @feature = feature
        @feature_no_ext = @ext ? feature[0...(-@ext.size)] : feature
        @base = File.basename(@feature_no_ext)
      end

      def ==(other)
        # The looked up feature has to be the trailing part of an already-part_of_index entry.
        # We always want to check part_of_index_feature.end_with?(lookup_feature).
        # We compare extensions only if the lookup_feature has an extension.

        if @part_of_index
          stored = self
          lookup = other
        elsif other.part_of_index
          stored = other
          lookup = self
        else
          raise 'Expected that at least one of the FeatureEntry instances is part of the index'
        end

        if lookup.ext
          stored.feature.end_with?(lookup.feature)
        else
          stored.feature_no_ext.end_with?(lookup.feature_no_ext)
        end
      end
      alias_method :eql?, :==

      def hash
        @base.hash
      end
    end

    def self.find_file(feature)
      feature = File.expand_path(feature) if feature.start_with?('~')
      Primitive.find_file(feature)
    end

    # MRI: search_required
    def self.find_feature_or_file(feature)
      feature_ext = extension_symbol(feature)
      if feature_ext
        case feature_ext
        when :rb
          if feature_provided?(feature, false)
            return [:feature_loaded, nil]
          end
          path = find_file(feature)
          return expanded_path_provided(path) if path
          return [:not_found, nil]
        when :so
          if feature_provided?(feature, false)
            return [:feature_loaded, nil]
          else
            feature_no_ext = feature[0...-3] # remove ".so"
            path = find_file("#{feature_no_ext}.#{Truffle::Platform::DLEXT}")
            return expanded_path_provided(path) if path
          end
        when :dlext
          if feature_provided?(feature, false)
            return [:feature_loaded, nil]
          else
            path = find_file(feature)
            return expanded_path_provided(path) if path
          end
        end
      else
        found = feature_provided?(feature, false)
        if found == :rb
          return [:feature_loaded, nil]
        end
      end

      path = find_file(feature)
      if path
        if feature_provided?(path, true)
          [:feature_loaded, nil]
        else
          [:feature_found, path]
        end
      else
        if found
          [:feature_loaded, nil]
        else
          [:not_found, nil]
        end
      end
    end

    def self.expanded_path_provided(path)
      if feature_provided?(path, true)
        [:feature_loaded, nil]
      else
        [:feature_found, path]
      end
    end

    # MRI: rb_feature_p
    # Whether feature is already loaded, i.e., part of $LOADED_FEATURES,
    # using the @loaded_features_index to lookup faster.
    # expanded is true if feature is an expanded path (and exists).
    def self.feature_provided?(feature, expanded)
      feature_ext = extension_symbol(feature)
      feature_has_rb_ext = feature_ext == :rb

      with_synchronized_features do
        get_loaded_features_index
        feature_entry = FeatureEntry.new(feature)
        if @loaded_features_index.key?(feature_entry)
          @loaded_features_index[feature_entry].each do |i|
            loaded_feature = $LOADED_FEATURES[i]

            next if loaded_feature.size < feature.size
            feature_path = if loaded_feature.start_with?(feature)
                             feature
                           else
                             if expanded
                               nil
                             else
                               loaded_feature_path(loaded_feature, feature, $LOAD_PATH)
                             end
                           end
            if feature_path
              loaded_feature_ext = extension_symbol(loaded_feature)
              if !loaded_feature_ext
                return :unknown unless feature_ext
              else
                if (!feature_has_rb_ext || !feature_ext) && binary_ext?(loaded_feature_ext)
                  return :so
                end
                if (feature_has_rb_ext || !feature_ext) && loaded_feature_ext == :rb
                  return :rb
                end
              end
            end
          end
        end

        false
      end
    end

    # MRI: loaded_feature_path
    # Search if $LOAD_PATH[i]/feature corresponds to loaded_feature.
    # Returns the $LOAD_PATH entry containing feature.
    def self.loaded_feature_path(loaded_feature, feature, load_path)
      name_ext = extension(loaded_feature)
      load_path.find do |p|
        loaded_feature == "#{p}/#{feature}#{name_ext}" || loaded_feature == "#{p}/#{feature}"
      end
    end

    # MRI: rb_provide_feature
    # Add feature to $LOADED_FEATURES and the index, called from RequireNode
    def self.provide_feature(feature)
      raise '$LOADED_FEATURES is frozen; cannot append feature' if $LOADED_FEATURES.frozen?
      #feature.freeze # TODO freeze these but post-boot.rb issue using replace
      with_synchronized_features do
        get_loaded_features_index
        $LOADED_FEATURES << feature
        features_index_add(feature, $LOADED_FEATURES.size - 1)
        @loaded_features_copy = $LOADED_FEATURES.dup
      end
    end

    def self.binary_ext?(ext)
      ext == :so || ext == :dlext
    end

    # Done this way to avoid many duplicate Strings representing the file extensions
    def self.extension_symbol(path)
      if !Primitive.nil?(path)
        if path.end_with?('.rb')
          :rb
        elsif path.end_with?('.so')
          :so
        elsif path.end_with?(DOT_DLEXT)
          :dlext
        else
          ext = File.extname(path)
          ext.empty? ? nil : :other
        end
      else
        nil
      end
    end

    # Done this way to avoid many duplicate Strings representing the file extensions
    def self.extension(path)
      if !Primitive.nil?(path)
        if path.end_with?('.rb')
          '.rb'
        elsif path.end_with?('.so')
          '.so'
        elsif path.end_with?(DOT_DLEXT)
          DOT_DLEXT
        else
          ext = File.extname(path)
          ext.empty? ? nil : ext
        end
      else
        nil
      end
    end

    def self.with_synchronized_features
      TruffleRuby.synchronized($LOADED_FEATURES) do
        yield
      end
    end

    # MRI: get_loaded_features_index
    # always called inside #with_synchronized_features
    def self.get_loaded_features_index
      unless Primitive.array_storage_equal?(@loaded_features_copy, $LOADED_FEATURES)
        @loaded_features_index.clear
        $LOADED_FEATURES.map! do |val|
          val = StringValue(val)
          #val.freeze # TODO freeze these but post-boot.rb issue using replace
          val
        end
        $LOADED_FEATURES.each_with_index do |val, idx|
          features_index_add(val, idx)
        end
        @loaded_features_copy = $LOADED_FEATURES.dup
      end
      @loaded_features_index
    end

    # MRI: features_index_add
    # always called inside #with_synchronized_features
    def self.features_index_add(feature, offset)
      feature_entry = FeatureEntry.new(feature)
      if @loaded_features_index.key?(feature_entry)
        @loaded_features_index[feature_entry] << offset
      else
        @loaded_features_index[feature_entry] = [offset]
        feature_entry.part_of_index = true
      end
    end

  end
end
