class CardConstants {
  /// reference ID used to match the common back of all cards
  static const sharedBackReferenceId = 'pokemon-shared-back';

  /// the maximum amount of front card candidates used for detailed matching
  static const candidateLimit = 48;

  /// number of ORB feature descriptors stored per card in the dataset
  static const featuresPerCard = 96;

  /// size of each binary ORB descriptor in bytes
  static const descriptorSize = 32;

  /// number of card references for each dataset shard
  static const shardSize = 8;

  /// portrait width-to-height ratio of a Pokemon card (63 mm x 88 mm)
  static const cardAspectRatio = 63 / 88;
}
